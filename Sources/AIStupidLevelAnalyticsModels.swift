import Foundation

struct DashboardAlertsResponse: Decodable {
    let success: Bool
    let data: [DashboardAlert]
}

struct DashboardAlert: Codable, Identifiable, Hashable {
    var id: String { "\(name)-\(detectedAt ?? "")" }
    let name: String
    let provider: String
    let issue: String?
    let severity: String?
    let detectedAt: String?
}

struct DashboardBatchStatusResponse: Decodable {
    let success: Bool
    let data: DashboardBatchStatusData
}

struct DashboardBatchStatusData: Codable {
    let isBatchInProgress: Bool?
    let schedulerRunning: Bool?
    let nextScheduledRun: String?
}

struct AnalyticsRecommendationsResponse: Decodable {
    let success: Bool
    let data: AnalyticsRecommendationsPayload
}

struct AnalyticsRecommendationsPayload: Codable {
    let bestForCode: AnalyticsRecommendationSlot?
    let mostReliable: AnalyticsRecommendationSlot?
    let fastestResponse: AnalyticsRecommendationSlot?
    let avoidNow: [AnalyticsRecommendationSlot]?
}

struct AnalyticsRecommendationSlot: Codable, Hashable {
    let id: String?
    let name: String?
    let vendor: String?
    let score: Double?
    let lastUpdate: String?
    let displayScore: Double?
    let rank: Int?
    let reason: String?
    let evidence: String?
    let correctness: Double?
    let codeQuality: Double?
    let stabilityScore: Double?
}

struct AnalyticsDegradationsResponse: Decodable {
    let success: Bool
    let data: [AnalyticsDegradationItem]
}

struct AnalyticsDegradationItem: Codable, Identifiable, Hashable {
    var id: String { "\(modelId)-\(detectedAt ?? "")" }
    let modelId: Int
    let modelName: String?
    let provider: String?
    let currentScore: Double?
    let baselineScore: Double?
    let dropPercentage: Double?
    let severity: String?
    let detectedAt: String?
    let message: String?
    let type: String?
}

struct ProviderReliabilityResponse: Decodable {
    let success: Bool
    let data: [ProviderReliabilityRow]
    let timestamp: String?
}

struct ProviderReliabilityRow: Codable, Identifiable, Hashable {
    var id: String { provider }
    let provider: String
    let trustScore: Int?
    let totalIncidents: Int?
    let incidentsPerMonth: Int?
    let avgRecoveryHours: String?
    let lastIncident: String?
    let trend: String?
    let isAvailable: Bool?
}

struct BenchmarkModelDetail: Codable, Hashable {
    let id: Int
    let name: String
    let vendor: String
    let version: String?
    let notes: String?
    let createdAt: String?
    let displayName: String?
    let showInRankings: Bool?
    let supportsToolCalling: Bool?
    let maxToolsPerCall: Int?
    let toolCallReliability: Double?
    let usesReasoningEffort: Bool?
    let latestScore: BenchmarkModelLatestScore?
}

struct BenchmarkModelLatestScore: Codable, Hashable {
    let id: Int?
    let modelId: Int?
    let ts: String?
    let stupidScore: Double?
    let axes: BenchmarkModelAxes?
    let cusum: Double?
    let note: String?
    let suite: String?
    let confidenceLower: Double?
    let confidenceUpper: Double?
    let standardError: Double?
    let sampleSize: Int?
    let modelVariance: Double?
    let displayScore: Double?
}

struct BenchmarkModelAxes: Codable, Hashable {
    let correctness: Double?
    let spec: Double?
    let complexity: Double?
    let codeQuality: Double?
    let efficiency: Double?
    let stability: Double?
    let refusal: Double?
    let edgeCases: Double?
    let recovery: Double?
    let debugging: Double?
    let format: Double?
    let safety: Double?
}

struct BenchmarkModelStats: Codable, Hashable {
    let modelId: Int
    let currentScore: Double?
    let totalRuns: Int?
    let successfulRuns: Int?
    let successRate: Double?
    let averageCorrectness: Double?
    let averageLatency: Double?
    let debug: BenchmarkModelStatsDebug?
}

struct BenchmarkModelStatsDebug: Codable, Hashable {
    let period: String?
    let sortBy: String?
    let suite: String?
    let calculationMethod: String?
}

struct ModelHistoryPayload: Codable {
    let modelId: Int
    let period: String?
    let sortBy: String?
    let dataPoints: Int?
    let timeRange: ModelHistoryTimeRange?
    let history: [ModelHistoryPoint]
}

struct ModelHistoryPoint: Codable, Hashable {
    let timestamp: String
    let stupidScore: Double?
    let displayScore: Double?
}

struct ModelHistoryTimeRange: Codable, Hashable {
    let rawValue: String?
    let from: String?
    let to: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let rawValue = try? container.decode(String.self) {
            self.rawValue = rawValue
            self.from = nil
            self.to = nil
            return
        }

        let object = try container.decode(TimeRangeObject.self)
        self.rawValue = nil
        self.from = object.from
        self.to = object.to
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let rawValue {
            try container.encode(rawValue)
        } else {
            try container.encode(TimeRangeObject(from: from, to: to))
        }
    }

    private struct TimeRangeObject: Codable, Hashable {
        let from: String?
        let to: String?
    }
}
