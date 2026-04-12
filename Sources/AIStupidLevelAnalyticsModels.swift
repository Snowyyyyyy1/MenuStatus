import Foundation

struct DashboardAlertsResponse: Decodable {
    let success: Bool
    let data: [DashboardAlert]
}

struct DashboardAlert: Decodable, Identifiable, Hashable {
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

struct DashboardBatchStatusData: Decodable {
    let isBatchInProgress: Bool?
    let schedulerRunning: Bool?
    let nextScheduledRun: String?
}

struct AnalyticsRecommendationsResponse: Decodable {
    let success: Bool
    let data: AnalyticsRecommendationsPayload
}

struct AnalyticsRecommendationsPayload: Decodable {
    let bestForCode: AnalyticsRecommendationSlot?
    let mostReliable: AnalyticsRecommendationSlot?
    let fastestResponse: AnalyticsRecommendationSlot?
    let avoidNow: [AnalyticsRecommendationSlot]?
}

struct AnalyticsRecommendationSlot: Decodable, Hashable {
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

struct AnalyticsDegradationItem: Decodable, Identifiable, Hashable {
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

struct ProviderReliabilityRow: Decodable, Identifiable, Hashable {
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

struct ModelHistoryPayload: Decodable {
    let modelId: Int
    let period: String?
    let sortBy: String?
    let dataPoints: Int?
    let timeRange: String?
    let history: [ModelHistoryPoint]
}

struct ModelHistoryPoint: Decodable, Hashable {
    let timestamp: String
    let stupidScore: Double?
    let displayScore: Double?
}
