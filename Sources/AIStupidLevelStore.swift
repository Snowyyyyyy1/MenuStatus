import Foundation
import Observation

@MainActor
@Observable
final class AIStupidLevelStore {
    struct Fetcher {
        let fetchScores: @Sendable () async throws -> [BenchmarkScore]
        let fetchGlobalIndex: @Sendable () async throws -> GlobalIndex
        let fetchDashboardAlerts: @Sendable () async throws -> [DashboardAlert]
        let fetchBatchStatus: @Sendable () async throws -> DashboardBatchStatusData
        let fetchRecommendations: @Sendable () async throws -> AnalyticsRecommendationsPayload
        let fetchDegradations: @Sendable () async throws -> [AnalyticsDegradationItem]
        let fetchProviderReliability: @Sendable () async throws -> [ProviderReliabilityRow]

        static let live = Fetcher(
            fetchScores: { try await AIStupidLevelClient.fetchScores() },
            fetchGlobalIndex: { try await AIStupidLevelClient.fetchGlobalIndex() },
            fetchDashboardAlerts: { try await AIStupidLevelClient.fetchDashboardAlerts() },
            fetchBatchStatus: { try await AIStupidLevelClient.fetchBatchStatus() },
            fetchRecommendations: { try await AIStupidLevelClient.fetchRecommendations() },
            fetchDegradations: { try await AIStupidLevelClient.fetchDegradations() },
            fetchProviderReliability: { try await AIStupidLevelClient.fetchProviderReliability() }
        )
    }

    var scores: [BenchmarkScore] = []
    var globalIndex: GlobalIndex?
    var dashboardAlerts: [DashboardAlert] = []
    var batchStatus: DashboardBatchStatusData?
    var recommendations: AnalyticsRecommendationsPayload?
    var degradations: [AnalyticsDegradationItem] = []
    var providerReliability: [ProviderReliabilityRow] = []
    var historyByModelID: [String: ModelHistoryPayload] = [:]
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private var historyFetchTasks: [String: Task<Void, Never>] = [:]
    private(set) var pollInterval: TimeInterval = 300

    var hasVisibleContent: Bool {
        globalIndex != nil
            || !scores.isEmpty
            || !dashboardAlerts.isEmpty
            || !degradations.isEmpty
            || !providerReliability.isEmpty
            || recommendations?.bestForCode != nil
            || recommendations?.mostReliable != nil
            || recommendations?.fastestResponse != nil
            || !(recommendations?.avoidNow?.isEmpty ?? true)
    }

    func startPolling(interval: TimeInterval) {
        stopPolling()
        pollInterval = max(60, interval)
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                do {
                    try await Task.sleep(for: .seconds(self?.pollInterval ?? 300))
                } catch {
                    if Task.isCancelled { break }
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refreshNow() async {
        await refreshNow(fetcher: .live)
    }

    func refreshNow(fetcher: Fetcher) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        let fetchResults = await Self.fetchAll(
            existing: Snapshot(
                scores: scores,
                globalIndex: globalIndex,
                dashboardAlerts: dashboardAlerts,
                batchStatus: batchStatus,
                recommendations: recommendations,
                degradations: degradations,
                providerReliability: providerReliability
            ),
            fetcher: fetcher
        )

        scores = fetchResults.scores
        globalIndex = fetchResults.globalIndex
        dashboardAlerts = fetchResults.dashboardAlerts
        batchStatus = fetchResults.batchStatus
        recommendations = fetchResults.recommendations
        degradations = fetchResults.degradations
        providerReliability = fetchResults.providerReliability
        if !fetchResults.errors.isEmpty {
            errorMessage = fetchResults.errors.joined(separator: "\n")
        }

        lastRefreshed = Date()
        isLoading = false
    }

    func loadHistoryIfNeeded(modelId: String) {
        if historyByModelID[modelId] != nil { return }
        if historyFetchTasks[modelId] != nil { return }

        historyFetchTasks[modelId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.historyFetchTasks[modelId] = nil }
            do {
                let payload = try await AIStupidLevelClient.fetchModelHistory(modelId: modelId)
                self.historyByModelID[modelId] = payload
            } catch {
                // Extension data failures are intentionally silent.
            }
        }
    }

    private struct Snapshot {
        var scores: [BenchmarkScore]
        var globalIndex: GlobalIndex?
        var dashboardAlerts: [DashboardAlert]
        var batchStatus: DashboardBatchStatusData?
        var recommendations: AnalyticsRecommendationsPayload?
        var degradations: [AnalyticsDegradationItem]
        var providerReliability: [ProviderReliabilityRow]
    }

    private struct FetchResults {
        var scores: [BenchmarkScore]
        var globalIndex: GlobalIndex?
        var dashboardAlerts: [DashboardAlert]
        var batchStatus: DashboardBatchStatusData?
        var recommendations: AnalyticsRecommendationsPayload?
        var degradations: [AnalyticsDegradationItem]
        var providerReliability: [ProviderReliabilityRow]
        var errors: [String] = []

        init(existing: Snapshot) {
            scores = existing.scores
            globalIndex = existing.globalIndex
            dashboardAlerts = existing.dashboardAlerts
            batchStatus = existing.batchStatus
            recommendations = existing.recommendations
            degradations = existing.degradations
            providerReliability = existing.providerReliability
        }
    }

    nonisolated private static func fetchAll(
        existing: Snapshot,
        fetcher: Fetcher
    ) async -> FetchResults {
        enum FetchResult {
            case scores(Result<[BenchmarkScore], Error>)
            case globalIndex(Result<GlobalIndex, Error>)
            case dashboardAlerts(Result<[DashboardAlert], Error>)
            case batchStatus(Result<DashboardBatchStatusData, Error>)
            case recommendations(Result<AnalyticsRecommendationsPayload, Error>)
            case degradations(Result<[AnalyticsDegradationItem], Error>)
            case providerReliability(Result<[ProviderReliabilityRow], Error>)
        }

        var results = FetchResults(existing: existing)

        await withTaskGroup(of: FetchResult.self) { group in
            group.addTask {
                do {
                    return .scores(.success(try await fetcher.fetchScores()))
                } catch {
                    return .scores(.failure(error))
                }
            }

            group.addTask {
                do {
                    return .globalIndex(.success(try await fetcher.fetchGlobalIndex()))
                } catch {
                    return .globalIndex(.failure(error))
                }
            }

            group.addTask {
                do {
                    return .dashboardAlerts(.success(try await fetcher.fetchDashboardAlerts()))
                } catch {
                    return .dashboardAlerts(.failure(error))
                }
            }

            group.addTask {
                do {
                    return .batchStatus(.success(try await fetcher.fetchBatchStatus()))
                } catch {
                    return .batchStatus(.failure(error))
                }
            }

            group.addTask {
                do {
                    return .recommendations(.success(try await fetcher.fetchRecommendations()))
                } catch {
                    return .recommendations(.failure(error))
                }
            }

            group.addTask {
                do {
                    return .degradations(.success(try await fetcher.fetchDegradations()))
                } catch {
                    return .degradations(.failure(error))
                }
            }

            group.addTask {
                do {
                    return .providerReliability(.success(try await fetcher.fetchProviderReliability()))
                } catch {
                    return .providerReliability(.failure(error))
                }
            }

            for await result in group {
                switch result {
                case .scores(.success(let scores)):
                    results.scores = scores
                case .scores(.failure(let error)):
                    results.errors.append("Benchmark scores: \(error.localizedDescription)")
                case .globalIndex(.success(let index)):
                    results.globalIndex = index
                case .globalIndex(.failure(let error)):
                    results.errors.append("Global index: \(error.localizedDescription)")
                case .dashboardAlerts(.success(let alerts)):
                    results.dashboardAlerts = alerts
                case .dashboardAlerts(.failure):
                    break
                case .batchStatus(.success(let batchStatus)):
                    results.batchStatus = batchStatus
                case .batchStatus(.failure):
                    break
                case .recommendations(.success(let recommendations)):
                    results.recommendations = recommendations
                case .recommendations(.failure):
                    break
                case .degradations(.success(let degradations)):
                    results.degradations = degradations
                case .degradations(.failure):
                    break
                case .providerReliability(.success(let providerReliability)):
                    results.providerReliability = providerReliability
                case .providerReliability(.failure):
                    break
                }
            }
        }

        return results
    }
}
