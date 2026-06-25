import Foundation
import Network
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

    private struct DashboardPayloadFingerprint: Encodable {
        let scores: [BenchmarkScore]
        let globalIndex: GlobalIndex?
        let dashboardAlerts: [DashboardAlert]
        let batchStatus: DashboardBatchStatusData?
        let recommendations: AnalyticsRecommendationsPayload?
        let degradations: [AnalyticsDegradationItem]
        let providerReliability: [ProviderReliabilityRow]
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
    private var hoverCacheTimestamps: [String: Date] = [:]
    private var pathMonitor: NWPathMonitor?
    private var debounceTask: Task<Void, Never>?
    private var currentRefresh: Task<Void, Never>?
    private var refreshGeneration: Int = 0
    private var lastPersistedDashboardFingerprint: Data?
    private(set) var pollInterval: TimeInterval = 300
    private(set) var isConnected = true

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.now = now
        restorePersistentDashboardSnapshot()
        restorePersistentHoverCache()
    }

    deinit {
        MainActor.assumeIsolated {
            stopPolling()
            for (_, task) in hoverFetchTasks { task.cancel() }
            hoverFetchTasks.removeAll()
        }
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
        modelDetailsByID[modelId] != nil
            && modelStatsByModelID[modelId] != nil
            && historyByModelID[modelId] != nil
    }

    private static let popoverStaleThreshold: TimeInterval = 60

    func startPolling(interval: TimeInterval) {
        stopPolling()
        pollInterval = max(60, interval)
        startNetworkMonitor()
        startPollingLoop()
    }

    private func startPollingLoop() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.isConnected {
                    await self.refreshNow()
                }
                do {
                    try await Task.sleep(for: .seconds(self?.pollInterval ?? 300))
                } catch {
                    if Task.isCancelled { break }
                }
            }
        }
    }

    func refreshIfStale() async {
        let isStale = lastRefreshed.map { now().timeIntervalSince($0) > Self.popoverStaleThreshold } ?? true
        guard isStale else { return }
        await refreshNow()
        // See StatusStore.refreshIfStale — reset polling sleep to avoid back-to-back fetches.
        startPollingLoop()
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        stopNetworkMonitor()
    }

    private func startNetworkMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathChange(connected)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.snowyy.MenuStatus.network.benchmark"))
    }

    private func stopNetworkMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func handlePathChange(_ connected: Bool) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else { return }
            let wasDisconnected = !self.isConnected
            if self.isConnected != connected { self.isConnected = connected }
            if connected, wasDisconnected {
                if self.errorMessage != nil { self.errorMessage = nil }
                // Same race fix as StatusStore: cancel the in-flight refresh,
                // then startPollingLoop replaces the cancelled polling task.
                self.currentRefresh?.cancel()
                self.startPollingLoop()
            } else if !connected {
                if self.errorMessage != nil { self.errorMessage = nil }
            }
        }
    }

    func refreshNow() async {
        await refreshNow(fetcher: .live)
    }

    func refreshNow(fetcher: Fetcher) async {
        // See StatusStore.refreshNow for the rationale — task-based queueing replaces the
        // bool guard so the reconnect race ("new polling sees isLoading=true and bails") is gone.
        if let inflight = currentRefresh {
            await inflight.value
        }
        if Task.isCancelled { return }

        refreshGeneration += 1
        let myGeneration = refreshGeneration
        let task = Task<Void, Never> { @MainActor in
            await self.performRefresh(fetcher: fetcher)
        }
        currentRefresh = task
        await task.value
        if refreshGeneration == myGeneration {
            currentRefresh = nil
        }
    }

    private func performRefresh(fetcher: Fetcher) async {
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
        if modelDetailsByID[modelId] != nil
            || modelStatsByModelID[modelId] != nil
            || historyByModelID[modelId] != nil {
            hoverCacheTimestamps[modelId] = now()
        }
        // Enforce after inserting so the cap is exact (not off-by-one) and the just-written
        // model — which has the newest timestamp — is never the one evicted.
        enforceHoverCacheLimit()
        persistHoverCacheEntryIfAvailable(for: modelId)
    }

    private func enforceHoverCacheLimit() {
        let maxEntries = PersistentCache.maxEntries
        // Count across the union of all three caches (tracked by hoverCacheTimestamps) so a
        // model with only stats/history can't grow unbounded when its detail fetch keeps
        // failing. `keys.prefix` would have evicted arbitrary hash-ordered keys, not the
        // oldest — sort by cache timestamp instead.
        guard hoverCacheTimestamps.count > maxEntries else { return }
        let overflow = hoverCacheTimestamps.count - maxEntries
        let oldestKeys = hoverCacheTimestamps
            .sorted { $0.value < $1.value }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            modelDetailsByID.removeValue(forKey: key)
            modelStatsByModelID.removeValue(forKey: key)
            historyByModelID.removeValue(forKey: key)
            hoverCacheTimestamps.removeValue(forKey: key)
        }
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
        static let dashboardSoftTTL: TimeInterval = 86400
        static let ttl: TimeInterval = 600
        static let maxEntries = 24
        static let hoverCacheDefaultsKey = "benchmarkHoverPayloadCache"
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    private func restorePersistentDashboardSnapshot() {
        guard
            let data = defaults.data(forKey: PersistentCache.dashboardKey),
            let snapshot = try? Self.decoder.decode(PersistedDashboardSnapshot.self, from: data),
            snapshot.cachedAt >= now().addingTimeInterval(-PersistentCache.dashboardSoftTTL)
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
        let fingerprintInput = DashboardPayloadFingerprint(
            scores: scores,
            globalIndex: globalIndex,
            dashboardAlerts: dashboardAlerts,
            batchStatus: batchStatus,
            recommendations: recommendations,
            degradations: degradations,
            providerReliability: providerReliability
        )
        let fingerprint = try? Self.encoder.encode(fingerprintInput)
        if let fingerprint, fingerprint == lastPersistedDashboardFingerprint {
            return
        }

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

        guard let data = try? Self.encoder.encode(snapshot) else { return }
        defaults.set(data, forKey: PersistentCache.dashboardKey)
        lastPersistedDashboardFingerprint = fingerprint
    }

    private func restorePersistentHoverCache() {
        let cache = loadPersistentHoverCache()
        guard !cache.isEmpty else { return }

        for (modelId, entry) in cache {
            modelDetailsByID[modelId] = entry.detail
            modelStatsByModelID[modelId] = entry.stats
            historyByModelID[modelId] = entry.history
            hoverCacheTimestamps[modelId] = entry.cachedAt
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
            let data = defaults.data(forKey: PersistentCache.hoverCacheDefaultsKey),
            let decoded = try? Self.decoder.decode([String: PersistedHoverCacheEntry].self, from: data)
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
            defaults.removeObject(forKey: PersistentCache.hoverCacheDefaultsKey)
            return
        }

        guard let data = try? Self.encoder.encode(limited) else { return }
        defaults.set(data, forKey: PersistentCache.hoverCacheDefaultsKey)
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
