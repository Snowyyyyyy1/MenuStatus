import Foundation

// MARK: - Provider

enum Provider: String, CaseIterable, Hashable {
    case openAI
    case anthropic

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Claude"
        }
    }

    var apiURL: URL {
        switch self {
        case .openAI: URL(string: "https://status.openai.com/api/v2/summary.json")!
        case .anthropic: URL(string: "https://status.claude.com/api/v2/summary.json")!
        }
    }

    var statusPageURL: URL {
        switch self {
        case .openAI: URL(string: "https://status.openai.com")!
        case .anthropic: URL(string: "https://status.claude.com")!
        }
    }
}

// MARK: - Client

struct StatusClient {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func fetchSummary(for provider: Provider) async throws -> StatuspageSummary {
        let data = try await fetchData(from: provider.apiURL)
        return try decoder.decode(StatuspageSummary.self, from: data)
    }

    static func fetchOpenAIOfficialHistory() async throws -> OfficialHistorySnapshot {
        let data = try await fetchData(from: Provider.openAI.statusPageURL)
        return try parseOpenAIOfficialHistoryHTML(data)
    }

    static func fetchAnthropicOfficialHistory() async throws -> OfficialHistorySnapshot {
        let data = try await fetchData(from: Provider.anthropic.statusPageURL)
        return try parseAnthropicOfficialHistoryHTML(data)
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

    static func parseOpenAIOfficialHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
        guard let html = String(data: data, encoding: .utf8) else {
            throw OpenAIHistoryParseError.invalidHTML
        }

        let decodedBlocks = try extractDecodedNextBlocks(from: html)

        guard let summaryBlock = decodedBlocks.first(where: { $0.contains(#""summary":{"#) }) else {
            throw OpenAIHistoryParseError.missingSummary
        }

        guard let dataBlock = decodedBlocks.first(where: { $0.contains(#""data":{"component_impacts""#) }) else {
            throw OpenAIHistoryParseError.missingHistoryData
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

    static func parseAnthropicOfficialHistoryHTML(_ data: Data) throws -> OfficialHistorySnapshot {
        guard let html = String(data: data, encoding: .utf8) else {
            throw AnthropicHistoryParseError.invalidHTML
        }

        let generatedAt = parseAnthropicGeneratedAt(in: html)
        let componentBlocks = try extractAnthropicComponentBlocks(from: html)
        let components = Dictionary(uniqueKeysWithValues: componentBlocks.map { ($0.id, $0) })

        return OfficialHistorySnapshot(generatedAt: generatedAt, groups: [], componentsByID: components)
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

        return parseISO(String(text[range]))
    }

    private static func parseAnthropicGeneratedAt(in html: String) -> Date? {
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

        return OfficialHistorySnapshot(generatedAt: generatedAt, groups: groups, componentsByID: mappedComponents)
    }

    private static func extractAnthropicComponentBlocks(from html: String) throws -> [OfficialHistoryComponent] {
        let marker = #"<div data-component-id=""#
        let componentRanges = allRanges(of: marker, in: html)

        return componentRanges.enumerated().compactMap { index, startIndex in
            let endIndex = index + 1 < componentRanges.count ? componentRanges[index + 1] : html.endIndex
            let block = String(html[startIndex..<endIndex])
            return parseAnthropicComponentBlock(block)
        }
    }

    private static func parseAnthropicComponentBlock(_ html: String) -> OfficialHistoryComponent? {
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

        let fills = extractAnthropicFills(from: svg)
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

    private static func extractAnthropicFills(from svg: String) -> [String] {
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
            throw OpenAIHistoryParseError.missingMarker(marker)
        }

        let suffix = text[markerRange.upperBound...]
        guard let objectStart = suffix.firstIndex(of: "{") else {
            throw OpenAIHistoryParseError.missingObjectAfterMarker(marker)
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

        throw OpenAIHistoryParseError.unterminatedObject(marker)
    }

    private static func sanitizeEmbeddedJSON(_ json: String) -> String {
        json.replacingOccurrences(of: #""$undefined""#, with: "null")
    }

    private static func parseISO(_ value: String) -> Date? {
        iso.date(from: value) ?? isoFallback.date(from: value)
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum OpenAIHistoryParseError: Error {
    case invalidHTML
    case missingSummary
    case missingHistoryData
    case missingMarker(String)
    case missingObjectAfterMarker(String)
    case unterminatedObject(String)
}

enum AnthropicHistoryParseError: Error {
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
