import Foundation

// MARK: - Client

struct StatusClient {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func fetchSummary(for provider: ProviderConfig) async throws -> StatuspageSummary {
        let data = try await fetchData(from: provider.apiURL)
        return try decoder.decode(StatuspageSummary.self, from: data)
    }

    static func fetchIncidents(for provider: ProviderConfig) async throws -> [Incident] {
        var components = URLComponents(url: provider.baseURL.appendingPathComponent("api/v2/incidents.json"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "per_page", value: "100")]
        let data = try await fetchData(from: components.url!)
        let response = try decoder.decode(IncidentHistoryResponse.self, from: data)
        return response.incidents
    }

    static func fetchScheduledMaintenances(for provider: ProviderConfig) async throws -> [Incident] {
        let url = provider.baseURL.appendingPathComponent("api/v2/scheduled-maintenances.json")
        let data = try await fetchData(from: url)
        let response = try decoder.decode(ScheduledMaintenancesResponse.self, from: data)
        return response.scheduledMaintenances
    }

    static func fetchHistoryPageIncidents(for provider: ProviderConfig) async throws -> [HistoryPageIncident] {
        guard provider.platform == .atlassianStatuspage else { return [] }
        let data = try await fetchData(from: provider.statusPageURL.appendingPathComponent("history"))
        return parseAtlassianHistoryPage(data)
    }

    static func fetchOfficialHistory(for provider: ProviderConfig) async throws -> OfficialHistorySnapshot {
        let data = try await fetchData(from: provider.statusPageURL)
        switch provider.platform {
        case .incidentIO:
            var snapshot = try parseIncidentIOHistoryHTML(data)
            // Fetch /history for incident names
            if let historyData = try? await fetchData(from: provider.statusPageURL.appendingPathComponent("history")),
               let names = try? parseIncidentIOIncidentNames(historyData) {
                snapshot = OfficialHistorySnapshot(
                    generatedAt: snapshot.generatedAt,
                    groups: snapshot.groups,
                    componentsByID: snapshot.componentsByID,
                    incidentNames: names
                )
            }
            return snapshot
        case .atlassianStatuspage:
            return try parseAtlassianStatuspageHistoryHTML(data)
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

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateHTTPResponse(response, for: url)
        return data
    }

    static func parseIncidentIOHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
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

        let summaryJSON = try sanitizeEmbeddedJSON(extractJSONObject(after: #""summary":"#, in: summaryBlock))
        let dataJSON = try sanitizeEmbeddedJSON(extractJSONObject(after: #""data":"#, in: dataBlock))

        let summary = try decoder.decode(OpenAIOfficialSummary.self, from: Data(summaryJSON.utf8))
        let historyData = try decoder.decode(OpenAIOfficialHistoryData.self, from: Data(dataJSON.utf8))

        let generatedAt = parseGeneratedAt(in: summaryBlock)
        return makeOfficialHistorySnapshot(
            generatedAt: generatedAt,
            summary: summary,
            data: historyData
        )
    }

    static func parseAtlassianStatuspageHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
        guard let html = String(data: data, encoding: .utf8) else {
            throw AtlassianStatuspageParseError.invalidHTML
        }

        let generatedAt = parseStatuspageGeneratedAt(in: html)
        let componentBlocks = try extractStatuspageComponentBlocks(from: html)
        let components = Dictionary(uniqueKeysWithValues: componentBlocks.map { ($0.id, $0) })

        return OfficialHistorySnapshot(generatedAt: generatedAt, groups: [], componentsByID: components, incidentNames: [:])
    }

    static func parseIncidentIOIncidentNames(_ data: Data) throws -> [String: String] {
        guard let html = String(data: data, encoding: .utf8) else { return [:] }
        let decodedBlocks = (try? extractDecodedNextBlocks(from: html)) ?? []

        var names: [String: String] = [:]
        for block in decodedBlocks {
            // Find incident objects with "id" and "name" fields
            let pattern = #""id":"([^"]+)"[^}]*?"name":"([^"]+)""#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            let range = NSRange(block.startIndex..<block.endIndex, in: block)
            for match in regex.matches(in: block, range: range) {
                guard match.numberOfRanges == 3,
                      let idRange = Range(match.range(at: 1), in: block),
                      let nameRange = Range(match.range(at: 2), in: block) else { continue }
                let id = String(block[idRange])
                let name = String(block[nameRange])
                // Only store incident-like IDs (not component/group IDs)
                if id.count > 20 {
                    names[id] = name
                }
            }
        }
        return names
    }

    private static func parseGeneratedAt(in text: String) -> Date? {
        let pattern = #""initialNow":\{"isoDate":"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return DateParsing.parseISODate(String(text[range]))
    }

    private static func parseStatuspageGeneratedAt(in html: String) -> Date? {
        let pattern = #"<meta\s+name="issued"\s+content="([0-9]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html),
              let issued = TimeInterval(html[range]) else {
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
        let componentsByID = Dictionary(uniqueKeysWithValues: groupEntries.flatMap { group in
            group.components.map { ($0.componentId, $0) }
        })

        let groups = groupEntries.map { group in
            return OfficialHistoryGroup(
                id: group.id,
                name: group.name,
                hidden: group.hidden,
                componentIDs: group.components.map(\.componentId),
                uptimePercent: uptimeByGroupID[group.id]
            )
        }

        let mappedComponents = Dictionary(uniqueKeysWithValues: groups.flatMap { group in
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
        })

        return OfficialHistorySnapshot(generatedAt: generatedAt, groups: groups, componentsByID: mappedComponents, incidentNames: [:])
    }

    private static func extractStatuspageComponentBlocks(from html: String) throws -> [OfficialHistoryComponent] {
        let marker = #"<div data-component-id=""#
        let componentRanges = allRanges(of: marker, in: html)

        return componentRanges.enumerated().compactMap { index, startIndex in
            let endIndex = index + 1 < componentRanges.count ? componentRanges[index + 1] : html.endIndex
            let block = String(html[startIndex..<endIndex])
            return parseStatuspageComponentBlock(block)
        }
    }

    private static func parseStatuspageComponentBlock(_ html: String) -> OfficialHistoryComponent? {
        guard let componentId = firstMatch(in: html, pattern: #"<div\s+data-component-id="([^"]+)""#, group: 1),
              let name = firstMatch(in: html, pattern: #"<span class="name">\s*(.*?)\s*</span>"#, group: 1),
              let svg = firstMatch(
                in: html,
                pattern: #"<svg class="availability-time-line-graphic".*?>(.*?)</svg>"#,
                group: 1,
                options: [.dotMatchesLineSeparators]
              ),
              let uptimeString = firstMatch(
                in: html,
                pattern: #"<span id="uptime-percent-[^"]+">\s*<var data-var="uptime-percent">([0-9]+(?:\.[0-9]+)?)</var>"#,
                group: 1
              ),
              let uptimePercent = Double(uptimeString) else {
            return nil
        }

        let fills = extractStatuspageFills(from: svg)
        guard !fills.isEmpty else { return nil }

        return OfficialHistoryComponent(
            id: componentId,
            name: decodeHTML(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            hidden: false,
            displayUptime: true,
            dataAvailableSince: nil,
            uptimePercent: uptimePercent,
            timelineSource: .colors(fills)
        )
    }

    private static func extractStatuspageFills(from svg: String) -> [String] {
        let pattern = #"<rect[^>]*\bfill="(#[0-9A-Fa-f]{6})"[^>]*class="[^"]*\buptime-day\b[^"]*\bday-([0-9]+)\b[^"]*"[^>]*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(svg.startIndex..<svg.endIndex, in: svg)

        let indexedFills: [(Int, String)] = regex.matches(in: svg, options: [], range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let fillRange = Range(match.range(at: 1), in: svg),
                  let dayRange = Range(match.range(at: 2), in: svg),
                  let day = Int(svg[dayRange]) else {
                return nil
            }
            return (day, String(svg[fillRange]))
        }

        return indexedFills.sorted { $0.0 < $1.0 }.map(\.1)
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

    private static func firstMatch(
        in text: String,
        pattern: String,
        group: Int,
        options: NSRegularExpression.Options = [.caseInsensitive]
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
              ),
              match.numberOfRanges > group,
              let range = Range(match.range(at: group), in: text) else {
            return nil
        }

        return String(text[range])
    }

    private static func extractDecodedNextBlocks(from html: String) throws -> [String] {
        let pattern = #"self\.__next_f\.push\(\[1,"(.*?)"\]\)</script>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)

        return try regex.matches(in: html, options: [], range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let raw = String(html[range])
            return try decodeJSONStringLiteral(raw)
        }
    }

    private static func decodeJSONStringLiteral(_ raw: String) throws -> String {
        let wrapped = "\"\(raw)\""
        return try JSONDecoder().decode(String.self, from: Data(wrapped.utf8))
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

    private static func sanitizeEmbeddedJSON(_ json: String) -> String {
        json.replacingOccurrences(of: #""$undefined""#, with: "null")
    }

    static func parseAtlassianHistoryPage(_ data: Data) -> [HistoryPageIncident] {
        guard let html = String(data: data, encoding: .utf8) else { return [] }

        // Extract data-react-props JSON
        let propsPattern = #"data-react-props="([^"]*)"#
        guard let propsRegex = try? NSRegularExpression(pattern: propsPattern),
              let propsMatch = propsRegex.firstMatch(
                in: html,
                range: NSRange(html.startIndex..<html.endIndex, in: html)
              ),
              let propsRange = Range(propsMatch.range(at: 1), in: html) else {
            return []
        }

        let escaped = String(html[propsRange])
        let unescaped = decodeHTML(escaped)
        guard let propsData = unescaped.data(using: .utf8),
              let props = try? JSONSerialization.jsonObject(with: propsData) as? [String: Any],
              let months = props["months"] as? [[String: Any]] else {
            return []
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
                let dayPattern = #"data-var='date'>(\d+)</var>"#
                guard let dayRegex = try? NSRegularExpression(pattern: dayPattern),
                      let dayMatch = dayRegex.firstMatch(
                        in: timestamp,
                        range: NSRange(timestamp.startIndex..<timestamp.endIndex, in: timestamp)
                      ),
                      let dayRange = Range(dayMatch.range(at: 1), in: timestamp),
                      let day = Int(timestamp[dayRange]) else { continue }

                // Parse times from: "<var data-var='time'>00:53</var> - <var data-var='time'>04:44</var>"
                let timePattern = #"data-var='time'>(\d{2}:\d{2})</var>"#
                let timeRegex = (try? NSRegularExpression(pattern: timePattern)) ?? NSRegularExpression()
                let timeMatches = timeRegex.matches(
                    in: timestamp,
                    range: NSRange(timestamp.startIndex..<timestamp.endIndex, in: timestamp)
                )

                var comps = DateComponents()
                comps.year = year
                comps.month = monthNum
                comps.day = day
                comps.timeZone = TimeZone(identifier: "UTC")

                guard let baseDate = calendar.date(from: comps) else { continue }

                var startDate = baseDate
                var endDate = baseDate.addingTimeInterval(3600) // default 1 hour

                if timeMatches.count >= 2,
                   let startRange = Range(timeMatches[0].range(at: 1), in: timestamp),
                   let endRange = Range(timeMatches[1].range(at: 1), in: timestamp) {
                    let startTime = String(timestamp[startRange])
                    let endTime = String(timestamp[endRange])
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
                } else if timeMatches.count == 1,
                          let startRange = Range(timeMatches[0].range(at: 1), in: timestamp) {
                    let startTime = String(timestamp[startRange])
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
