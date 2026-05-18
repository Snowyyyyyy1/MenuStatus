import Foundation

// MARK: - Client

struct StatusClient {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func fetchSummary(for provider: ProviderConfig) async throws -> StatuspageSummary {
        try await adapter(for: provider).fetchSummary(for: provider)
    }

    static func fetchIncidents(for provider: ProviderConfig) async throws -> [Incident] {
        try await adapter(for: provider).fetchIncidents(for: provider)
    }

    static func fetchScheduledMaintenances(for provider: ProviderConfig) async throws -> [Incident] {
        try await adapter(for: provider).fetchScheduledMaintenances(for: provider)
    }

    static func fetchHistoryPageIncidents(for provider: ProviderConfig) async throws -> [HistoryPageIncident] {
        try await adapter(for: provider).fetchHistoryPageIncidents(for: provider)
    }

    static func fetchOfficialHistory(for provider: ProviderConfig) async throws -> OfficialHistorySnapshot {
        try await adapter(for: provider).fetchOfficialHistory(for: provider)
    }

    static func adapter(for provider: ProviderConfig) -> any StatusProviderAdapter {
        switch provider.effectivePlatform {
        case .flashduty:
            FlashdutyStatusProviderAdapter()
        case .incidentIO:
            IncidentIOStatusProviderAdapter()
        case .atlassianStatuspage:
            AtlassianStatuspageProviderAdapter()
        }
    }

    static func validateHTTPResponse(_ response: URLResponse, for url: URL) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StatusClientTransportError.invalidResponse(url)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw StatusClientTransportError.unsuccessfulStatusCode(url: url, statusCode: httpResponse.statusCode)
        }
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response, for: url)
        return data
    }

    static func parseIncidentIOHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
        // Scope HTML and decoded blocks so they're released before JSON decoding
        let summaryJSON: String
        let dataJSON: String
        let generatedAt: Date?
        do {
            guard let html = String(data: data, encoding: .utf8) else {
                throw IncidentIOParseError.invalidHTML
            }
            let decodedBlocks = try extractDecodedNextBlocks(from: html)

            guard let summaryBlock = decodedBlocks.first(where: { $0.contains(#""summary":{"#) }) else {
                throw IncidentIOParseError.missingSummary
            }
            guard let dataBlock = decodedBlocks.first(where: { $0.contains(#""data":{"component_impacts""#) }) else {
                throw IncidentIOParseError.missingHistoryData
            }

            summaryJSON = try sanitizeEmbeddedJSON(extractJSONObject(after: #""summary":"#, in: summaryBlock))
            dataJSON = try sanitizeEmbeddedJSON(extractJSONObject(after: #""data":"#, in: dataBlock))
            generatedAt = parseGeneratedAt(in: summaryBlock)
        }

        let summary = try decoder.decode(OpenAIOfficialSummary.self, from: Data(summaryJSON.utf8))
        let historyData = try decoder.decode(OpenAIOfficialHistoryData.self, from: Data(dataJSON.utf8))

        return makeOfficialHistorySnapshot(
            generatedAt: generatedAt,
            summary: summary,
            data: historyData
        )
    }

    static func parseAtlassianStatuspageHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
        let generatedAt: Date?
        let paletteOverrides: [String: TimelineDayLevel]
        let componentBlocks: [OfficialHistoryComponent]
        do {
            guard let html = String(data: data, encoding: .utf8) else {
                throw AtlassianStatuspageParseError.invalidHTML
            }
            generatedAt = parseStatuspageGeneratedAt(in: html)
            paletteOverrides = parseStatuspagePaletteOverrides(in: html)
            componentBlocks = try extractStatuspageComponentBlocks(from: html, paletteOverrides: paletteOverrides)
        }
        let components = Dictionary(componentBlocks.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        return OfficialHistorySnapshot(generatedAt: generatedAt, groups: [], componentsByID: components, incidentNames: [:])
    }

    static func parseIncidentIOIncidentNames(_ data: Data) throws -> [String: String] {
        let decodedBlocks: [String]
        do {
            guard let html = String(data: data, encoding: .utf8) else { return [:] }
            decodedBlocks = (try? extractDecodedNextBlocks(from: html)) ?? []
        }

        let regex = /"id":"([^"]+)"[^}]*?"name":"([^"]+)"/.dotMatchesNewlines()
        var names: [String: String] = [:]
        for block in decodedBlocks {
            for match in block.matches(of: regex) {
                let id = String(match.1)
                let name = String(match.2)
                // Only store incident-like IDs (not component/group IDs)
                if id.count > 20 {
                    names[id] = name
                }
            }
        }
        return names
    }

    private static func parseGeneratedAt(in text: String) -> Date? {
        guard let match = text.firstMatch(of: /"initialNow":\{"isoDate":"([^"]+)"/) else {
            return nil
        }
        return DateParsing.parseISODate(String(match.1))
    }

    private static func parseStatuspageGeneratedAt(in html: String) -> Date? {
        guard let match = html.firstMatch(of: /<meta\s+name="issued"\s+content="([0-9]+)"/.ignoresCase()),
              let issued = TimeInterval(match.1) else {
            return nil
        }
        return Date(timeIntervalSince1970: issued)
    }

    private static func makeOfficialHistorySnapshot(
        generatedAt: Date?,
        summary: OpenAIOfficialSummary,
        data: OpenAIOfficialHistoryData
    ) -> OfficialHistorySnapshot {
        let groupedImpacts = data.impactsByComponentID
        let uptimeByComponentID = data.uptimeByComponentID
        let uptimeByGroupID = data.uptimeByGroupID
        let groupEntries = summary.structure.items.compactMap(\.group)
        let componentsByID = Dictionary(groupEntries.flatMap { group in
            group.components.map { ($0.componentId, $0) }
        }, uniquingKeysWith: { _, new in new })

        let groups = groupEntries.map { group in
            return OfficialHistoryGroup(
                id: group.id,
                name: group.name,
                hidden: group.hidden,
                componentIDs: group.components.map(\.componentId),
                uptimePercent: uptimeByGroupID[group.id]
            )
        }

        let mappedComponents = Dictionary(groups.flatMap { group in
            group.componentIDs.compactMap { componentID -> (String, OfficialHistoryComponent)? in
                guard let component = componentsByID[componentID] else {
                    return nil
                }

                let officialComponent = OfficialHistoryComponent(
                    id: component.componentId,
                    name: component.name,
                    hidden: component.hidden,
                    displayUptime: component.displayUptime ?? true,
                    dataAvailableSince: component.dataAvailableSince,
                    uptimePercent: uptimeByComponentID[component.componentId],
                    timelineSource: .impacts(groupedImpacts[component.componentId] ?? [])
                )
                return (componentID, officialComponent)
            }
        }, uniquingKeysWith: { _, new in new })

        return OfficialHistorySnapshot(generatedAt: generatedAt, groups: groups, componentsByID: mappedComponents, incidentNames: [:])
    }

    static func parseFlashdutySummaryHTML(_ data: Data, sourceURL: URL) throws -> StatuspageSummary {
        let html = try flashdutyHTML(from: data)
        let pageConfig = try parseFlashdutyPageConfig(fromHTML: html)
        let activeChanges = (try? parseFlashdutyActiveChanges(fromHTML: html)) ?? []
        let statusByComponentID = flashdutyActiveStatusByComponentID(activeChanges)
        let components = pageConfig.components
            .sorted { ($0.orderId ?? Int.max, $0.componentId) < ($1.orderId ?? Int.max, $1.componentId) }
            .map { component in
                Component(
                    id: component.componentId,
                    name: component.name,
                    status: statusByComponentID[component.componentId] ?? .operational,
                    position: component.orderId,
                    description: component.description,
                    startDate: component.availableSinceSeconds.map(isoStringFromUnixSeconds),
                    groupId: nil,
                    group: false,
                    onlyShowIfDegraded: false
                )
            }
        let overallStatus = components.map(\.status).max() ?? .operational
        let incidents = activeChanges.map { change in
            Incident(
                id: String(change.changeId),
                name: change.title,
                status: flashdutyIncidentStatus(change.status),
                impact: statusIndicator(for: (change.affectedComponents.map(\.status).max()?.componentStatus) ?? overallStatus),
                shortlink: nil,
                startedAt: nil,
                createdAt: nil,
                updatedAt: nil,
                monitoringAt: nil,
                resolvedAt: nil,
                incidentUpdates: nil,
                components: change.affectedComponents.map {
                    IncidentComponent(id: $0.componentId, name: $0.name, status: $0.status.componentStatus)
                }
            )
        }

        return StatuspageSummary(
            page: StatusPage(
                id: String(pageConfig.pageId),
                name: pageConfig.name,
                url: sourceURL.absoluteString,
                timeZone: "Etc/UTC",
                updatedAt: nil
            ),
            status: OverallStatus(
                indicator: statusIndicator(for: overallStatus),
                description: statusDescription(for: overallStatus)
            ),
            components: components,
            incidents: incidents,
            scheduledMaintenances: nil
        )
    }

    static func parseFlashdutyHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
        let html = try flashdutyHTML(from: data)
        let pageConfig = try parseFlashdutyPageConfig(fromHTML: html)
        let historyData = (try? parseFlashdutyHistoryData(fromHTML: html)) ?? FlashdutyHistoryData.empty

        let uptimeByComponentID = Dictionary(
            historyData.componentUptimes.compactMap { uptime -> (String, Double)? in
                guard let componentID = uptime.componentId, let percentage = uptime.uptimePercent else { return nil }
                return (componentID, percentage)
            },
            uniquingKeysWith: { _, new in new }
        )
        let impactsByComponentID = Dictionary(
            grouping: historyData.componentImpacts.compactMap { impact -> OfficialComponentImpact? in
                guard let officialStatus = impact.status.officialImpactStatus else { return nil }
                return OfficialComponentImpact(
                    componentId: impact.componentId,
                    endAt: isoStringFromUnixSeconds(impact.endAtSeconds),
                    startAt: isoStringFromUnixSeconds(impact.startAtSeconds),
                    status: officialStatus,
                    statusPageIncidentId: String(impact.changeId)
                )
            },
            by: \.componentId
        )
        let components = Dictionary(
            pageConfig.components.map { component in
                (
                    component.componentId,
                    OfficialHistoryComponent(
                        id: component.componentId,
                        name: component.name,
                        hidden: false,
                        displayUptime: true,
                        dataAvailableSince: component.availableSinceSeconds.map(isoStringFromUnixSeconds),
                        uptimePercent: uptimeByComponentID[component.componentId],
                        timelineSource: .impacts(impactsByComponentID[component.componentId] ?? [])
                    )
                )
            },
            uniquingKeysWith: { _, new in new }
        )
        let incidentNames = Dictionary(
            historyData.linkedChanges.map { (String($0.id), $0.title) },
            uniquingKeysWith: { _, new in new }
        )
        let generatedAt = historyData.timeRange.map { Date(timeIntervalSince1970: TimeInterval($0.to)) }

        return OfficialHistorySnapshot(
            generatedAt: generatedAt,
            groups: [],
            componentsByID: components,
            incidentNames: incidentNames
        )
    }

    static func parseFlashdutyPageConfig(_ data: Data) throws -> FlashdutyPageConfig {
        try parseFlashdutyPageConfig(fromHTML: try flashdutyHTML(from: data))
    }

    private static func extractStatuspageComponentBlocks(
        from html: String,
        paletteOverrides: [String: TimelineDayLevel]
    ) throws -> [OfficialHistoryComponent] {
        let marker = #"<div data-component-id=""#
        let componentRanges = allRanges(of: marker, in: html)

        return componentRanges.enumerated().compactMap { index, startIndex in
            let endIndex = index + 1 < componentRanges.count ? componentRanges[index + 1] : html.endIndex
            let block = String(html[startIndex..<endIndex])
            return parseStatuspageComponentBlock(block, paletteOverrides: paletteOverrides)
        }
    }

    private static func parseStatuspageComponentBlock(
        _ html: String,
        paletteOverrides: [String: TimelineDayLevel]
    ) -> OfficialHistoryComponent? {
        guard let componentIdMatch = html.firstMatch(of: /<div\s+data-component-id="([^"]+)"/),
              let nameMatch = html.firstMatch(of: /<span class="name">\s*(.*?)\s*<\/span>/),
              let svgMatch = html.firstMatch(of: /<svg class="availability-time-line-graphic".*?>(.*?)<\/svg>/.dotMatchesNewlines()),
              let uptimeMatch = html.firstMatch(of: /<span id="uptime-percent-[^"]+">\s*<var data-var="uptime-percent">([0-9]+(?:\.[0-9]+)?)<\/var>/),
              let uptimePercent = Double(uptimeMatch.1) else {
            return nil
        }
        let componentId = String(componentIdMatch.1)
        let name = String(nameMatch.1)
        let svg = String(svgMatch.1)

        let levels = extractStatuspageLevels(from: svg, paletteOverrides: paletteOverrides)
        guard !levels.isEmpty else { return nil }

        return OfficialHistoryComponent(
            id: componentId,
            name: decodeHTML(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            hidden: false,
            displayUptime: true,
            dataAvailableSince: nil,
            uptimePercent: uptimePercent,
            timelineSource: .levels(levels)
        )
    }

    private static func extractStatuspageLevels(
        from svg: String,
        paletteOverrides: [String: TimelineDayLevel]
    ) -> [TimelineDayLevel] {
        let rectRegex = /<rect\b[^>]*\/?>/
        let indexedLevels: [(Int, TimelineDayLevel)] = svg.matches(of: rectRegex).compactMap { match in
            let rect = String(match.0)
            guard let fillMatch = rect.firstMatch(of: /\bfill="(#[0-9A-Fa-f]{6})"/),
                  let classMatch = rect.firstMatch(of: /\bclass="([^"]*)"/) else {
                return nil
            }
            let className = String(classMatch.1)
            let classes = className.split(whereSeparator: \.isWhitespace)
            guard classes.contains(where: { $0 == "uptime-day" }),
                  let dayMatch = className.firstMatch(of: /\bday-([0-9]+)\b/),
                  let day = Int(dayMatch.1) else {
                return nil
            }
            let level = TimelineDayLevel.statuspageLevel(
                forFillHex: String(fillMatch.1),
                overrides: paletteOverrides
            )
            return (day, level)
        }
        return indexedLevels.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private struct StatuspageColorPalette: Decodable {
        let blue: String?
        let green: String?
        let noData: String?
        let orange: String?
        let red: String?
        let yellow: String?
    }

    private static func parseStatuspagePaletteOverrides(in html: String) -> [String: TimelineDayLevel] {
        guard let match = html.firstMatch(of: /window\.pageColorData\s*=\s*(\{[^;]*\});/.dotMatchesNewlines()),
              let data = String(match.1).data(using: .utf8),
              let palette = try? decoder.decode(StatuspageColorPalette.self, from: data) else {
            return [:]
        }

        let mapping: [(String?, TimelineDayLevel)] = [
            (palette.noData, .noData),
            (palette.green, .operational),
            (palette.yellow, .degraded),
            (palette.orange, .partialOutage),
            (palette.red, .majorOutage),
            (palette.blue, .maintenance),
        ]
        var overrides: [String: TimelineDayLevel] = [:]
        for (source, level) in mapping {
            guard let source else { continue }
            overrides[TimelineDayLevel.normalizedHex(source)] = level
        }
        return overrides
    }

    private static func flashdutyHTML(from data: Data) throws -> String {
        guard let html = String(data: data, encoding: .utf8) else {
            throw FlashdutyParseError.invalidHTML
        }
        return html
    }

    private static func parseFlashdutyPageConfig(fromHTML html: String) throws -> FlashdutyPageConfig {
        let decodedBlocks = try extractDecodedNextBlocks(from: html)
        for block in decodedBlocks where block.contains(#""initialPageConfig":{"#) {
            let json = try sanitizeEmbeddedJSON(extractJSONObject(after: #""initialPageConfig":"#, in: block))
            return try decoder.decode(FlashdutyPageConfig.self, from: Data(json.utf8))
        }
        for block in decodedBlocks where block.contains(#""page":{"#) {
            let json = try sanitizeEmbeddedJSON(extractJSONObject(after: #""page":"#, in: block))
            return try decoder.decode(FlashdutyPageConfig.self, from: Data(json.utf8))
        }
        throw FlashdutyParseError.missingPageConfig
    }

    private static func parseFlashdutyActiveChanges(fromHTML html: String) throws -> [FlashdutyChange] {
        let decodedBlocks = try extractDecodedNextBlocks(from: html)
        for block in decodedBlocks where block.contains(#""active_changes":"#) {
            let json = try sanitizeEmbeddedJSON(extractJSONArray(after: #""active_changes":"#, in: block))
            return try decoder.decode([FlashdutyChange].self, from: Data(json.utf8))
        }
        return []
    }

    private static func parseFlashdutyHistoryData(fromHTML html: String) throws -> FlashdutyHistoryData {
        let decodedBlocks = try extractDecodedNextBlocks(from: html)
        for block in decodedBlocks where block.contains(#""component_impacts":["#) {
            let json = try sanitizeEmbeddedJSON(extractJSONObject(after: #""initialData":"#, in: block))
            var historyData = try decoder.decode(FlashdutyHistoryData.self, from: Data(json.utf8))
            historyData.timeRange = try parseFlashdutyTimeRange(from: block)
            return historyData
        }
        return .empty
    }

    private static func parseFlashdutyTimeRange(from block: String) throws -> FlashdutyTimeRange? {
        guard block.contains(#""timeRange":{"#) else { return nil }
        let json = try sanitizeEmbeddedJSON(extractJSONObject(after: #""timeRange":"#, in: block))
        return try decoder.decode(FlashdutyTimeRange.self, from: Data(json.utf8))
    }

    private static func flashdutyActiveStatusByComponentID(_ changes: [FlashdutyChange]) -> [String: ComponentStatus] {
        var statuses: [String: ComponentStatus] = [:]
        for change in changes where flashdutyIncidentStatus(change.status).isActive {
            for component in change.affectedComponents {
                let status = component.status.componentStatus
                statuses[component.componentId] = max(statuses[component.componentId] ?? .operational, status)
            }
        }
        return statuses
    }

    private static func flashdutyIncidentStatus(_ status: String) -> IncidentStatus {
        switch status {
        case "resolved":
            .resolved
        case "monitoring":
            .monitoring
        case "identified":
            .identified
        default:
            .investigating
        }
    }

    private static func statusIndicator(for status: ComponentStatus) -> StatusIndicator {
        switch status {
        case .operational:
            .none
        case .degradedPerformance:
            .minor
        case .partialOutage, .underMaintenance:
            status == .underMaintenance ? .maintenance : .major
        case .majorOutage:
            .critical
        }
    }

    private static func statusDescription(for status: ComponentStatus) -> String {
        switch status {
        case .operational:
            "All Systems Operational"
        case .degradedPerformance:
            "Minor Issues"
        case .partialOutage:
            "Partial Outage"
        case .majorOutage:
            "Major Outage"
        case .underMaintenance:
            "Maintenance"
        }
    }

    private static func isoStringFromUnixSeconds(_ seconds: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func allRanges(of needle: String, in text: String) -> [String.Index] {
        var positions: [String.Index] = []
        var searchStart = text.startIndex

        while let range = text.range(of: needle, range: searchStart..<text.endIndex) {
            positions.append(range.lowerBound)
            searchStart = range.upperBound
        }

        return positions
    }

    private static func extractDecodedNextBlocks(from html: String) throws -> [String] {
        let regex = /self\.__next_f\.push\(\[1,"(.*?)"\]\)<\/script>/.dotMatchesNewlines()
        return try html.matches(of: regex).compactMap { match in
            let raw = String(match.1)
            return try decodeJSONStringLiteral(raw)
        }
    }

    private static func decodeJSONStringLiteral(_ raw: String) throws -> String {
        let wrapped = "\"\(raw)\""
        return try decoder.decode(String.self, from: Data(wrapped.utf8))
    }

    private static func extractJSONObject(after marker: String, in text: String) throws -> String {
        guard let markerRange = text.range(of: marker) else {
            throw IncidentIOParseError.missingMarker(marker)
        }

        let suffix = text[markerRange.upperBound...]
        guard let objectStart = suffix.firstIndex(of: "{") else {
            throw IncidentIOParseError.missingObjectAfterMarker(marker)
        }

        var depth = 0
        var inString = false
        var isEscaping = false
        var currentIndex = objectStart

        while currentIndex < text.endIndex {
            let character = text[currentIndex]

            if inString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"":
                    inString = true
                case "{":
                    depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        let endIndex = text.index(after: currentIndex)
                        return String(text[objectStart..<endIndex])
                    }
                default:
                    break
                }
            }

            currentIndex = text.index(after: currentIndex)
        }

        throw IncidentIOParseError.unterminatedObject(marker)
    }

    private static func extractJSONArray(after marker: String, in text: String) throws -> String {
        guard let markerRange = text.range(of: marker) else {
            throw IncidentIOParseError.missingMarker(marker)
        }

        let suffix = text[markerRange.upperBound...]
        guard let arrayStart = suffix.firstIndex(of: "[") else {
            throw IncidentIOParseError.missingObjectAfterMarker(marker)
        }

        var depth = 0
        var inString = false
        var isEscaping = false
        var currentIndex = arrayStart

        while currentIndex < text.endIndex {
            let character = text[currentIndex]

            if inString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                switch character {
                case "\"":
                    inString = true
                case "[":
                    depth += 1
                case "]":
                    depth -= 1
                    if depth == 0 {
                        let endIndex = text.index(after: currentIndex)
                        return String(text[arrayStart..<endIndex])
                    }
                default:
                    break
                }
            }

            currentIndex = text.index(after: currentIndex)
        }

        throw IncidentIOParseError.unterminatedObject(marker)
    }

    private static func sanitizeEmbeddedJSON(_ json: String) -> String {
        json.replacingOccurrences(of: #""$undefined""#, with: "null")
    }

    static func parseAtlassianHistoryPage(_ data: Data) -> [HistoryPageIncident] {
        let months: [[String: Any]]
        do {
            guard let html = String(data: data, encoding: .utf8) else { return [] }
            guard let propsMatch = html.firstMatch(of: /data-react-props="([^"]*)/) else { return [] }
            let escaped = String(propsMatch.1)
            let unescaped = decodeHTML(escaped)
            guard let propsData = unescaped.data(using: .utf8),
                  let props = try? JSONSerialization.jsonObject(with: propsData) as? [String: Any],
                  let m = props["months"] as? [[String: Any]] else { return [] }
            months = m
        }

        let calendar = Calendar(identifier: .gregorian)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        let monthNames = ["January": 1, "February": 2, "March": 3, "April": 4,
                          "May": 5, "June": 6, "July": 7, "August": 8,
                          "September": 9, "October": 10, "November": 11, "December": 12]

        var results: [HistoryPageIncident] = []

        for month in months {
            guard let monthName = month["name"] as? String,
                  let year = month["year"] as? Int,
                  let monthNum = monthNames[monthName],
                  let incidents = month["incidents"] as? [[String: Any]] else { continue }

            for inc in incidents {
                guard let code = inc["code"] as? String,
                      let name = inc["name"] as? String,
                      let timestamp = inc["timestamp"] as? String else { continue }

                let impactStr = inc["impact"] as? String
                let impact = impactStr.flatMap { StatusIndicator(rawValue: $0) }

                // Parse day from: "Mar <var data-var='date'>29</var>, ..."
                guard let dayMatch = timestamp.firstMatch(of: /data-var='date'>(\d+)<\/var>/),
                      let day = Int(dayMatch.1) else { continue }

                // Parse times from: "<var data-var='time'>00:53</var> - <var data-var='time'>04:44</var>"
                let timeMatches = timestamp.matches(of: /data-var='time'>(\d{2}:\d{2})<\/var>/)

                var comps = DateComponents()
                comps.year = year
                comps.month = monthNum
                comps.day = day
                comps.timeZone = TimeZone(identifier: "UTC")

                guard let baseDate = calendar.date(from: comps) else { continue }

                var startDate = baseDate
                var endDate = baseDate.addingTimeInterval(3600) // default 1 hour

                if timeMatches.count >= 2 {
                    let startTime = String(timeMatches[0].1)
                    let endTime = String(timeMatches[1].1)
                    let startParts = startTime.split(separator: ":").compactMap { Int($0) }
                    let endParts = endTime.split(separator: ":").compactMap { Int($0) }
                    if startParts.count == 2 {
                        startDate = baseDate.addingTimeInterval(TimeInterval(startParts[0] * 3600 + startParts[1] * 60))
                    }
                    if endParts.count == 2 {
                        var endOffset = TimeInterval(endParts[0] * 3600 + endParts[1] * 60)
                        if endOffset <= TimeInterval(startParts[0] * 3600 + startParts[1] * 60) {
                            endOffset += 86400 // crossed midnight
                        }
                        endDate = baseDate.addingTimeInterval(endOffset)
                    }
                } else if timeMatches.count == 1 {
                    let startTime = String(timeMatches[0].1)
                    let parts = startTime.split(separator: ":").compactMap { Int($0) }
                    if parts.count == 2 {
                        startDate = baseDate.addingTimeInterval(TimeInterval(parts[0] * 3600 + parts[1] * 60))
                        endDate = startDate.addingTimeInterval(3600)
                    }
                }

                results.append(HistoryPageIncident(
                    code: code,
                    name: name,
                    impact: impact,
                    startedAt: startDate,
                    resolvedAt: endDate
                ))
            }
        }

        return results
    }

}

enum IncidentIOParseError: Error {
    case invalidHTML
    case missingSummary
    case missingHistoryData
    case missingMarker(String)
    case missingObjectAfterMarker(String)
    case unterminatedObject(String)
}

enum AtlassianStatuspageParseError: Error {
    case invalidHTML
}

enum FlashdutyParseError: Error {
    case invalidHTML
    case missingPageConfig
}

enum StatusClientTransportError: LocalizedError, Equatable {
    case invalidResponse(URL)
    case unsuccessfulStatusCode(url: URL, statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let url):
            return "Invalid HTTP response from \(url.absoluteString)"
        case .unsuccessfulStatusCode(let url, let statusCode):
            return "HTTP \(statusCode) from \(url.absoluteString)"
        }
    }
}
