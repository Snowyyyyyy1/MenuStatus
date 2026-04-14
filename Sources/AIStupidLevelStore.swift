import Foundation
import Observation

@MainActor
@Observable
final class AIStupidLevelStore {
    private struct PersistedDashboardSnapshot: Codable {
        let cachedAt: Date
        let scores: [BenchmarkScore]
        let globalIndex: GlobalIndex?
        let dashboardAlerts: [DashboardAlert]
        let batchStatus: DashboardBatchStatusData?
        let recommendations: AnalyticsRecommendationsPayload?
        let degradations: [AnalyticsDegradationItem]
        let providerReliability: [ProviderReliabilityRow]
        let lastRefreshed: Date?
    }

    private struct PersistedHoverCacheEntry: Codable {
        let cachedAt: Date
        let detail: BenchmarkModelDetail
        let stats: BenchmarkModelStats
        let history: ModelHistoryPayload
    }

    struct Fetcher {
        let fetchScores: @Sendable () async throws -> [BenchmarkScore]
        let fetchGlobalIndex: @Sendable () async throws -> GlobalIndex
        let fetchDashboardAlerts: @Sendable () async throws -> [DashboardAlert]
        let fetchBatchStatus: @Sendable () async throws -> DashboardBatchStatusData
        let fetchRecommendations: @Sendable () async throws -> AnalyticsRecommendationsPayload
        let fetchDegradations: @Sendable () async throws -> [AnalyticsDegradationItem]
        let fetchProviderReliability: @Sendable () async throws -> [ProviderReliabilityRow]
        let fetchModelDetail: @Sendable (String) async throws -> BenchmarkModelDetail
        let fetchModelStats: @Sendable (String) async throws -> BenchmarkModelStats
        let fetchModelHistory: @Sendable (String) async throws -> ModelHistoryPayload

        init(
            fetchScores: @escaping @Sendable () async throws -> [BenchmarkScore],
            fetchGlobalIndex: @escaping @Sendable () async throws -> GlobalIndex,
            fetchDashboardAlerts: @escaping @Sendable () async throws -> [DashboardAlert],
            fetchBatchStatus: @escaping @Sendable () async throws -> DashboardBatchStatusData,
            fetchRecommendations: @escaping @Sendable () async throws -> AnalyticsRecommendationsPayload,
            fetchDegradations: @escaping @Sendable () async throws -> [AnalyticsDegradationItem],
            fetchProviderReliability: @escaping @Sendable () async throws -> [ProviderReliabilityRow],
            fetchModelDetail: @escaping @Sendable (String) async throws -> BenchmarkModelDetail = { _ in
                throw AIStupidLevelClientError.apiFailure("Model detail fetcher unavailable")
            },
            fetchModelStats: @escaping @Sendable (String) async throws -> BenchmarkModelStats = { _ in
                throw AIStupidLevelClientError.apiFailure("Model stats fetcher unavailable")
            },
            fetchModelHistory: @escaping @Sendable (String) async throws -> ModelHistoryPayload = { _ in
                throw AIStupidLevelClientError.apiFailure("Model history fetcher unavailable")
            }
        ) {
            self.fetchScores = fetchScores
            self.fetchGlobalIndex = fetchGlobalIndex
            self.fetchDashboardAlerts = fetchDashboardAlerts
            self.fetchBatchStatus = fetchBatchStatus
            self.fetchRecommendations = fetchRecommendations
            self.fetchDegradations = fetchDegradations
            self.fetchProviderReliability = fetchProviderReliability
            self.fetchModelDetail = fetchModelDetail
            self.fetchModelStats = fetchModelStats
            self.fetchModelHistory = fetchModelHistory
        }

        static let live = Fetcher(
            fetchScores: { try await AIStupidLevelClient.fetchScores() },
            fetchGlobalIndex: { try await AIStupidLevelClient.fetchGlobalIndex() },
            fetchDashboardAlerts: { try await AIStupidLevelClient.fetchDashboardAlerts() },
            fetchBatchStatus: { try await AIStupidLevelClient.fetchBatchStatus() },
            fetchRecommendations: { try await AIStupidLevelClient.fetchRecommendations() },
            fetchDegradations: { try await AIStupidLevelClient.fetchDegradations() },
            fetchProviderReliability: { try await AIStupidLevelClient.fetchProviderReliability() },
            fetchModelDetail: { try await AIStupidLevelClient.fetchModelDetail(modelId: $0) },
            fetchModelStats: { try await AIStupidLevelClient.fetchModelStats(modelId: $0) },
            fetchModelHistory: { try await AIStupidLevelClient.fetchModelHistory(modelId: $0) }
        )
    }

    var scores: [BenchmarkScore] = []
    var globalIndex: GlobalIndex?
    var dashboardAlerts: [DashboardAlert] = []
    var batchStatus: DashboardBatchStatusData?
    var recommendations: AnalyticsRecommendationsPayload?
    var degradations: [AnalyticsDegradationItem] = []
    var providerReliability: [ProviderReliabilityRow] = []
    var modelDetailsByID: [String: BenchmarkModelDetail] = [:]
    var modelStatsByModelID: [String: BenchmarkModelStats] = [:]
    var historyByModelID: [String: ModelHistoryPayload] = [:]
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?

    private let defaults: UserDefaults
    private let now: () -> Date
    private var pollingTask: Task<Void, Never>?
    private var hoverFetchTasks: [String: Task<HoverFetchPayload, Never>] = [:]
    private var resolvedHoverPayloadModelIDs: Set<String> = []
    private(set) var pollInterval: TimeInterval = 300

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
        restorePersistentDashboardSnapshot()
        restorePersistentHoverCache()
    }

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

    func hasResolvedHoverPayload(for modelId: String) -> Bool {
        resolvedHoverPayloadModelIDs.contains(modelId)
            || (modelDetailsByID[modelId] != nil
                && modelStatsByModelID[modelId] != nil
                && historyByModelID[modelId] != nil)
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

        lastRefreshed = now()
        persistDashboardSnapshot()
        isLoading = false
    }

    func loadHoverDataIfNeeded(modelId: String, fetcher: Fetcher = .live) async {
        let needsDetail = modelDetailsByID[modelId] == nil
        let needsStats = modelStatsByModelID[modelId] == nil
        let needsHistory = historyByModelID[modelId] == nil
        guard needsDetail || needsStats || needsHistory else { return }

        let task: Task<HoverFetchPayload, Never>
        if let existingTask = hoverFetchTasks[modelId] {
            task = existingTask
        } else {
            let newTask = Task {
                await Self.fetchHoverPayload(
                    modelId: modelId,
                    needsDetail: needsDetail,
                    needsStats: needsStats,
                    needsHistory: needsHistory,
                    fetcher: fetcher
                )
            }
            hoverFetchTasks[modelId] = newTask
            task = newTask
        }

        let payload = await task.value
        hoverFetchTasks[modelId] = nil

        if let detail = payload.detail {
            modelDetailsByID[modelId] = detail
        }
        if let stats = payload.stats {
            modelStatsByModelID[modelId] = stats
        }
        if let history = payload.history {
            historyByModelID[modelId] = history
        }
        resolvedHoverPayloadModelIDs.insert(modelId)
        persistHoverCacheEntryIfAvailable(for: modelId)
    }

    func prefetchHoverDataIfNeeded(modelIDs: [String], fetcher: Fetcher = .live) async {
        var seen = Set<String>()
        let uniqueModelIDs = modelIDs.filter { seen.insert($0).inserted }

        await withTaskGroup(of: Void.self) { group in
            for modelId in uniqueModelIDs {
                guard !hasResolvedHoverPayload(for: modelId) else { continue }
                group.addTask { [self] in
                    await loadHoverDataIfNeeded(modelId: modelId, fetcher: fetcher)
                }
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

    private struct HoverFetchPayload {
        let detail: BenchmarkModelDetail?
        let stats: BenchmarkModelStats?
        let history: ModelHistoryPayload?
    }

    private enum PersistentCache {
        static let dashboardKey = "benchmarkDashboardSnapshot"
        static let defaultsKey = "benchmarkHoverPayloadCache"
        static let ttl: TimeInterval = 600
        static let maxEntries = 24
    }

    private func restorePersistentDashboardSnapshot() {
        guard
            let data = defaults.data(forKey: PersistentCache.dashboardKey),
            let snapshot = try? JSONDecoder().decode(PersistedDashboardSnapshot.self, from: data),
            snapshot.cachedAt >= now().addingTimeInterval(-PersistentCache.ttl)
        else {
            defaults.removeObject(forKey: PersistentCache.dashboardKey)
            return
        }

        scores = snapshot.scores
        globalIndex = snapshot.globalIndex
        dashboardAlerts = snapshot.dashboardAlerts
        batchStatus = snapshot.batchStatus
        recommendations = snapshot.recommendations
        degradations = snapshot.degradations
        providerReliability = snapshot.providerReliability
        lastRefreshed = snapshot.lastRefreshed
    }

    private func persistDashboardSnapshot() {
        let snapshot = PersistedDashboardSnapshot(
            cachedAt: now(),
            scores: scores,
            globalIndex: globalIndex,
            dashboardAlerts: dashboardAlerts,
            batchStatus: batchStatus,
            recommendations: recommendations,
            degradations: degradations,
            providerReliability: providerReliability,
            lastRefreshed: lastRefreshed
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: PersistentCache.dashboardKey)
    }

    private func restorePersistentHoverCache() {
        let cache = loadPersistentHoverCache()
        guard !cache.isEmpty else { return }

        for (modelId, entry) in cache {
            modelDetailsByID[modelId] = entry.detail
            modelStatsByModelID[modelId] = entry.stats
            historyByModelID[modelId] = entry.history
            resolvedHoverPayloadModelIDs.insert(modelId)
        }
    }

    private func persistHoverCacheEntryIfAvailable(for modelId: String) {
        guard
            let detail = modelDetailsByID[modelId],
            let stats = modelStatsByModelID[modelId],
            let history = historyByModelID[modelId]
        else {
            return
        }

        var cache = loadPersistentHoverCache()
        cache[modelId] = PersistedHoverCacheEntry(
            cachedAt: now(),
            detail: detail,
            stats: stats,
            history: history
        )
        savePersistentHoverCache(cache)
    }

    private func loadPersistentHoverCache() -> [String: PersistedHoverCacheEntry] {
        guard
            let data = defaults.data(forKey: PersistentCache.defaultsKey),
            let decoded = try? JSONDecoder().decode([String: PersistedHoverCacheEntry].self, from: data)
        else {
            return [:]
        }

        let cutoff = now().addingTimeInterval(-PersistentCache.ttl)
        let filtered = decoded.filter { $0.value.cachedAt >= cutoff }
        if filtered.count != decoded.count {
            savePersistentHoverCache(filtered)
        }
        return filtered
    }

    private func savePersistentHoverCache(_ cache: [String: PersistedHoverCacheEntry]) {
        let sorted = cache.sorted { $0.value.cachedAt > $1.value.cachedAt }
        let limitedSlice = sorted[..<min(sorted.count, PersistentCache.maxEntries)]
        let limited = Dictionary(uniqueKeysWithValues: limitedSlice.map { ($0.key, $0.value) })

        if limited.isEmpty {
            defaults.removeObject(forKey: PersistentCache.defaultsKey)
            return
        }

        guard let data = try? JSONEncoder().encode(limited) else { return }
        defaults.set(data, forKey: PersistentCache.defaultsKey)
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

    nonisolated private static func fetchHoverPayload(
        modelId: String,
        needsDetail: Bool,
        needsStats: Bool,
        needsHistory: Bool,
        fetcher: Fetcher
    ) async -> HoverFetchPayload {
        async let detail: BenchmarkModelDetail? = needsDetail ? try? await fetcher.fetchModelDetail(modelId) : nil
        async let stats: BenchmarkModelStats? = needsStats ? try? await fetcher.fetchModelStats(modelId) : nil
        async let history: ModelHistoryPayload? = needsHistory ? try? await fetcher.fetchModelHistory(modelId) : nil

        return await HoverFetchPayload(
            detail: detail,
            stats: stats,
            history: history
        )
    }
}
