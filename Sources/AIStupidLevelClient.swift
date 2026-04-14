import Foundation

enum AIStupidLevelClientError: LocalizedError {
    case httpFailure(Int)
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .httpFailure(let code): "HTTP \(code)"
        case .apiFailure(let msg): msg
        }
    }
}

struct AIStupidLevelClient {
    static let baseURL = URL(string: "https://aistupidlevel.info")!

    static func modelDetailPageURL(modelId: String) -> URL? {
        baseURL.appendingPathComponent("models").appendingPathComponent(modelId)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static func fetchScores() async throws -> [BenchmarkScore] {
        try await fetchAndDecode(path: "/api/dashboard/scores", as: BenchmarkScoresResponse.self)
    }

    static func fetchGlobalIndex() async throws -> GlobalIndex {
        try await fetchAndDecode(path: "/api/dashboard/global-index", as: GlobalIndexResponse.self)
    }

    static func fetchDashboardAlerts() async throws -> [DashboardAlert] {
        try await fetchAndDecode(path: "/api/dashboard/alerts", as: DashboardAlertsResponse.self)
    }

    static func fetchBatchStatus() async throws -> DashboardBatchStatusData {
        try await fetchAndDecode(path: "/api/dashboard/batch-status", as: DashboardBatchStatusResponse.self)
    }

    static func fetchRecommendations() async throws -> AnalyticsRecommendationsPayload {
        try await fetchAndDecode(path: "/api/analytics/recommendations", as: AnalyticsRecommendationsResponse.self)
    }

    static func fetchDegradations() async throws -> [AnalyticsDegradationItem] {
        try await fetchAndDecode(path: "/api/analytics/degradations", as: AnalyticsDegradationsResponse.self)
    }

    static func fetchProviderReliability() async throws -> [ProviderReliabilityRow] {
        try await fetchAndDecode(path: "/api/analytics/provider-reliability", as: ProviderReliabilityResponse.self)
    }

    static func fetchModelDetail(modelId: String) async throws -> BenchmarkModelDetail {
        let data = try await fetchData(path: "/api/models/\(modelId)")
        return try decoder.decode(BenchmarkModelDetail.self, from: data)
    }

    static func fetchModelStats(
        modelId: String,
        period: String = "latest",
        sortBy: String = "combined"
    ) async throws -> BenchmarkModelStats {
        let data = try await fetchData(
            path: "/api/models/\(modelId)/stats",
            queryItems: [
                URLQueryItem(name: "period", value: period),
                URLQueryItem(name: "sortBy", value: sortBy)
            ]
        )
        return try decoder.decode(BenchmarkModelStats.self, from: data)
    }

    static func fetchModelHistory(modelId: String) async throws -> ModelHistoryPayload {
        let data = try await fetchData(path: "/api/models/\(modelId)/history")
        return try decoder.decode(ModelHistoryPayload.self, from: data)
    }

    // Keep decode methods accessible for unit tests
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
        try decoder.decode(BenchmarkModelDetail.self, from: data)
    }

    static func decodeModelStats(_ data: Data) throws -> BenchmarkModelStats {
        try decoder.decode(BenchmarkModelStats.self, from: data)
    }

    static func decodeModelHistory(_ data: Data) throws -> ModelHistoryPayload {
        try decoder.decode(ModelHistoryPayload.self, from: data)
    }

    // MARK: - Private

    private static func fetchAndDecode<R: APIResponse>(path: String, as type: R.Type) async throws -> R.Payload {
        let data = try await fetchData(path: path)
        return try decode(data, as: type)
    }

    private static func decode<R: APIResponse>(_ data: Data, as type: R.Type) throws -> R.Payload {
        let response = try decoder.decode(R.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("\(R.self) success=false") }
        return response.data
    }

    private static func fetchData(path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        let basePathURL = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: basePathURL, resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw AIStupidLevelClientError.apiFailure("Invalid URL for path \(path)")
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw AIStupidLevelClientError.httpFailure(-1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw AIStupidLevelClientError.httpFailure(http.statusCode)
        }
        return data
    }
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
