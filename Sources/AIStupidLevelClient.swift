import Foundation

enum AIStupidLevelErrorKind: Hashable, Sendable {
    case apiKeyRequired
    case authenticationFailed
    case rateLimited
    case unavailable
    case invalidResponse
}

enum AIStupidLevelClientError: LocalizedError, Sendable {
    case apiKeyRequired
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case httpFailure(statusCode: Int, message: String?)
    case apiFailure(String)
    case endpointUnavailable(String)
    case invalidURL(String)

    var kind: AIStupidLevelErrorKind {
        switch self {
        case .apiKeyRequired:
            return .apiKeyRequired
        case .authenticationFailed:
            return .authenticationFailed
        case .rateLimited:
            return .rateLimited
        case .httpFailure(let statusCode, _):
            return (statusCode == 401 || statusCode == 403) ? .authenticationFailed : .unavailable
        case .apiFailure, .endpointUnavailable, .invalidURL:
            return .invalidResponse
        }
    }

    var errorDescription: String? {
        switch self {
        case .apiKeyRequired:
            return "Benchmark API key is required"
        case .authenticationFailed:
            return "Benchmark API key was rejected"
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Benchmark API rate limit reached; retry after \(Int(retryAfter.rounded(.up))) seconds"
            }
            return "Benchmark API rate limit reached"
        case .httpFailure(let statusCode, let message):
            if let message, !message.isEmpty {
                return "HTTP \(statusCode): \(message)"
            }
            return "HTTP \(statusCode)"
        case .apiFailure(let message), .endpointUnavailable(let message), .invalidURL(let message):
            return message
        }
    }
}

struct AIStupidLevelClient {
    static let baseURL = URL(string: "https://aistupidlevel.info")!
    static let apiDocsURL = URL(string: "https://aistupidlevel.info/api-docs")!

    static func modelDetailPageURL(modelId: String) -> URL? {
        baseURL.appendingPathComponent("models").appendingPathComponent(modelId)
    }

    static var hasAPIKey: Bool {
        BenchmarkAPIKeyStore.load() != nil
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    // The benchmark service documents v1 as the supported API surface.
    static func fetchScores() async throws -> [BenchmarkScore] {
        try await fetchAndDecode(
            path: "/api/v1/models",
            queryItems: [
                URLQueryItem(name: "period", value: "latest"),
                URLQueryItem(name: "sortBy", value: "combined"),
            ],
            as: BenchmarkScoresResponse.self
        )
    }

    static func fetchGlobalIndex() async throws -> GlobalIndex {
        try await fetchAndDecode(path: "/api/v1/index", as: GlobalIndexResponse.self)
    }

    static func fetchDashboardAlerts() async throws -> [DashboardAlert] {
        try await fetchAndDecode(path: "/api/v1/alerts", as: DashboardAlertsResponse.self)
    }

    /// Kept for compatibility with old injected fetchers. There is no documented v1
    /// replacement, so the live store does not request this endpoint automatically.
    static func fetchBatchStatus() async throws -> DashboardBatchStatusData {
        try await fetchAndDecode(path: "/api/dashboard/batch-status", as: DashboardBatchStatusResponse.self)
    }

    static func fetchRecommendations() async throws -> AnalyticsRecommendationsPayload {
        try await fetchAndDecode(
            path: "/api/v1/analytics/recommendations",
            queryItems: [URLQueryItem(name: "period", value: "latest")],
            as: AnalyticsRecommendationsResponse.self
        )
    }

    static func fetchDegradations() async throws -> [AnalyticsDegradationItem] {
        try await fetchAndDecode(
            path: "/api/v1/analytics/degradations",
            queryItems: [URLQueryItem(name: "period", value: "latest")],
            as: AnalyticsDegradationsResponse.self
        )
    }

    static func fetchProviderReliability() async throws -> [ProviderReliabilityRow] {
        try await fetchAndDecode(
            path: "/api/v1/analytics/provider-reliability",
            queryItems: [URLQueryItem(name: "period", value: "latest")],
            as: ProviderReliabilityResponse.self
        )
    }

    static func fetchModelDetail(modelId: String) async throws -> BenchmarkModelDetail {
        let data = try await fetchData(path: "/api/v1/models/\(escapedPathComponent(modelId))")
        return try decodeEnvelopeOrRaw(data, as: BenchmarkModelDetail.self)
    }

    /// The service does not document a /stats route. Keep this method only so older
    /// callers/tests can report the endpoint as unsupported instead of making a 404.
    static func fetchModelStats(
        modelId _: String,
        period _: String = "latest",
        sortBy _: String = "combined"
    ) async throws -> BenchmarkModelStats {
        throw AIStupidLevelClientError.endpointUnavailable("Model statistics endpoint is not available")
    }

    static func fetchModelHistory(modelId: String) async throws -> ModelHistoryPayload {
        let data = try await fetchData(
            path: "/api/v1/models/\(escapedPathComponent(modelId))/history",
            queryItems: [URLQueryItem(name: "period", value: "latest")]
        )
        return try decodeEnvelopeOrRaw(data, as: ModelHistoryPayload.self)
    }

    // Keep decode methods accessible for unit tests.
    static func decodeScores(_ data: Data) throws -> [BenchmarkScore] {
        try decode(data, as: BenchmarkScoresResponse.self)
    }

    static func decodeGlobalIndex(_ data: Data) throws -> GlobalIndex {
        try decode(data, as: GlobalIndexResponse.self)
    }

    static func decodeDashboardAlerts(_ data: Data) throws -> [DashboardAlert] {
        try decode(data, as: DashboardAlertsResponse.self)
    }

    static func decodeBatchStatus(_ data: Data) throws -> DashboardBatchStatusData {
        try decode(data, as: DashboardBatchStatusResponse.self)
    }

    static func decodeRecommendations(_ data: Data) throws -> AnalyticsRecommendationsPayload {
        try decode(data, as: AnalyticsRecommendationsResponse.self)
    }

    static func decodeDegradations(_ data: Data) throws -> [AnalyticsDegradationItem] {
        try decode(data, as: AnalyticsDegradationsResponse.self)
    }

    static func decodeProviderReliability(_ data: Data) throws -> [ProviderReliabilityRow] {
        try decode(data, as: ProviderReliabilityResponse.self)
    }

    static func decodeModelDetail(_ data: Data) throws -> BenchmarkModelDetail {
        try decodeEnvelopeOrRaw(data, as: BenchmarkModelDetail.self)
    }

    static func decodeModelStats(_ data: Data) throws -> BenchmarkModelStats {
        try decodeEnvelopeOrRaw(data, as: BenchmarkModelStats.self)
    }

    static func decodeModelHistory(_ data: Data) throws -> ModelHistoryPayload {
        try decodeEnvelopeOrRaw(data, as: ModelHistoryPayload.self)
    }

    // MARK: - Private

    private static func fetchAndDecode<R: APIResponse>(
        path: String,
        queryItems: [URLQueryItem] = [],
        as type: R.Type
    ) async throws -> R.Payload {
        let data = try await fetchData(path: path, queryItems: queryItems)
        return try decode(data, as: type)
    }

    private static func decode<R: APIResponse>(_ data: Data, as type: R.Type) throws -> R.Payload {
        let response = try decoder.decode(R.self, from: data)
        guard response.success else {
            throw AIStupidLevelClientError.apiFailure("\(R.self) success=false")
        }
        return response.data
    }

    private static func decodeEnvelopeOrRaw<Payload: Decodable>(
        _ data: Data,
        as type: Payload.Type
    ) throws -> Payload {
        if let envelope = try? decoder.decode(APIEnvelope<Payload>.self, from: data) {
            guard envelope.success else {
                throw AIStupidLevelClientError.apiFailure("API response success=false")
            }
            return envelope.data
        }
        return try decoder.decode(type, from: data)
    }

    private static func fetchData(
        path: String,
        queryItems: [URLQueryItem] = [],
        apiKey: String? = nil
    ) async throws -> Data {
        let key = (apiKey ?? BenchmarkAPIKeyStore.load())?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else {
            throw AIStupidLevelClientError.apiKeyRequired
        }

        let basePathURL = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: basePathURL, resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw AIStupidLevelClientError.invalidURL("Invalid URL for path \(path)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIStupidLevelClientError.httpFailure(statusCode: -1, message: nil)
        }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIStupidLevelClientError.authenticationFailed
            }
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                throw AIStupidLevelClientError.rateLimited(retryAfter: retryAfter)
            }
            throw AIStupidLevelClientError.httpFailure(
                statusCode: http.statusCode,
                message: serverErrorMessage(from: data)
            )
        }
        return data
    }

    private static func serverErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        for key in ["message", "error", "detail"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func escapedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct APIEnvelope<Payload: Decodable>: Decodable {
    let success: Bool
    let data: Payload
}

// MARK: - APIResponse protocol for generic decode

private protocol APIResponse: Decodable {
    associatedtype Payload
    var success: Bool { get }
    var data: Payload { get }
}

extension BenchmarkScoresResponse: APIResponse {}
extension GlobalIndexResponse: APIResponse {}
extension DashboardAlertsResponse: APIResponse {}
extension DashboardBatchStatusResponse: APIResponse {}
extension AnalyticsRecommendationsResponse: APIResponse {}
extension AnalyticsDegradationsResponse: APIResponse {}
extension ProviderReliabilityResponse: APIResponse {}
