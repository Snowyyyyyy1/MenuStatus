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
        case .anthropic: URL(string: "https://status.anthropic.com/api/v2/summary.json")!
        }
    }

    var statusPageURL: URL {
        switch self {
        case .openAI: URL(string: "https://status.openai.com")!
        case .anthropic: URL(string: "https://status.anthropic.com")!
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
        let (data, _) = try await URLSession.shared.data(from: provider.apiURL)
        return try decoder.decode(StatuspageSummary.self, from: data)
    }

    static func fetchIncidents(for provider: Provider) async throws -> [Incident] {
        let url = provider.apiURL
            .deletingLastPathComponent()
            .appendingPathComponent("incidents.json")
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try decoder.decode(IncidentsResponse.self, from: data)
        return response.incidents
    }

    static func fetchOpenAIOfficialHistory() async throws -> OpenAIOfficialHistoryPayload {
        let (data, _) = try await URLSession.shared.data(from: Provider.openAI.statusPageURL)
        return try parseOpenAIOfficialHistoryHTML(data)
    }

    static func parseOpenAIOfficialHistoryHTML(_ data: Data) throws -> OpenAIOfficialHistoryPayload {
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
        return OpenAIOfficialHistoryPayload(
            generatedAt: generatedAt,
            summary: summary,
            data: historyData
        )
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
