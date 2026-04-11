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
        let data = try await fetchData(path: "/api/dashboard/scores")
        return try decodeScores(data)
    }

    static func fetchGlobalIndex() async throws -> GlobalIndex {
        let data = try await fetchData(path: "/api/dashboard/global-index")
        return try decodeGlobalIndex(data)
    }

    static func decodeScores(_ data: Data) throws -> [BenchmarkScore] {
        let response = try decoder.decode(BenchmarkScoresResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("scores response success=false") }
        return response.data
    }

    static func decodeGlobalIndex(_ data: Data) throws -> GlobalIndex {
        let response = try decoder.decode(GlobalIndexResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("global-index response success=false") }
        return response.data
    }

    private static func fetchData(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
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
