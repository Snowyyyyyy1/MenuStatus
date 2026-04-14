import XCTest
@testable import MenuStatus

final class AIStupidLevelStoreTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    actor CallCounter {
        private(set) var detailCalls = 0
        private(set) var statsCalls = 0
        private(set) var historyCalls = 0

        func recordDetail() { detailCalls += 1 }
        func recordStats() { statsCalls += 1 }
        func recordHistory() { historyCalls += 1 }

        func snapshot() -> (detail: Int, stats: Int, history: Int) {
            (detailCalls, statsCalls, historyCalls)
        }
    }

    actor ModelCallCounter {
        private var detailCalls: [String: Int] = [:]
        private var statsCalls: [String: Int] = [:]
        private var historyCalls: [String: Int] = [:]

        func recordDetail(for modelId: String) {
            detailCalls[modelId, default: 0] += 1
        }

        func recordStats(for modelId: String) {
            statsCalls[modelId, default: 0] += 1
        }

        func recordHistory(for modelId: String) {
            historyCalls[modelId, default: 0] += 1
        }

        func detailCount(for modelId: String) -> Int {
            detailCalls[modelId, default: 0]
        }

        func statsCount(for modelId: String) -> Int {
            statsCalls[modelId, default: 0]
        }

        func historyCount(for modelId: String) -> Int {
            historyCalls[modelId, default: 0]
        }
    }

    @MainActor
    func testHasVisibleContentReflectsLoadedBenchmarkSections() {
        let store = makeIsolatedStore(testName: #function)
        XCTAssertFalse(store.hasVisibleContent)

        store.globalIndex = makeGlobalIndex(score: 84)
        XCTAssertTrue(store.hasVisibleContent)

        store.globalIndex = nil
        store.providerReliability = [
            ProviderReliabilityRow(
                provider: "openai",
                trustScore: 81,
                totalIncidents: 1,
                incidentsPerMonth: 1,
                avgRecoveryHours: "1.2",
                lastIncident: nil,
                trend: "reliable",
                isAvailable: true
            )
        ]
        XCTAssertTrue(store.hasVisibleContent)
    }

    @MainActor
    func testHasResolvedHoverPayloadRequiresLoadedOrCompletedData() async {
        let store = makeIsolatedStore(testName: #function)

        XCTAssertFalse(store.hasResolvedHoverPayload(for: "38"))

        store.modelDetailsByID["38"] = makeModelDetail()
        XCTAssertFalse(store.hasResolvedHoverPayload(for: "38"))

        store.modelStatsByModelID["38"] = makeModelStats()
        XCTAssertFalse(store.hasResolvedHoverPayload(for: "38"))

        store.historyByModelID["38"] = makeModelHistory()
        XCTAssertTrue(store.hasResolvedHoverPayload(for: "38"))

        let partialStore = makeIsolatedStore(testName: "\(#function).partial")
        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { _ in self.makeModelDetail() },
            fetchModelStats: { _ in throw StubError.failed },
            fetchModelHistory: { _ in self.makeModelHistory() }
        )

        await partialStore.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)
        XCTAssertTrue(partialStore.hasResolvedHoverPayload(for: "38"))
    }

    @MainActor
    func testRefreshNowKeepsLastSuccessfulOptionalDataOnFailure() async {
        let store = makeIsolatedStore(testName: #function)
        store.dashboardAlerts = [
            DashboardAlert(name: "old-alert", provider: "openai", issue: nil, severity: "warning", detectedAt: nil)
        ]
        store.batchStatus = DashboardBatchStatusData(
            isBatchInProgress: false,
            schedulerRunning: true,
            nextScheduledRun: "2026-04-11T18:00:00.000Z"
        )
        store.recommendations = AnalyticsRecommendationsPayload(
            bestForCode: AnalyticsRecommendationSlot(
                id: "old-best",
                name: "gpt-old",
                vendor: "openai",
                score: 68,
                lastUpdate: nil,
                displayScore: 68,
                rank: 1,
                reason: "Previous winner",
                evidence: nil,
                correctness: nil,
                codeQuality: nil,
                stabilityScore: nil
            ),
            mostReliable: nil,
            fastestResponse: nil,
            avoidNow: []
        )
        store.degradations = [
            AnalyticsDegradationItem(
                modelId: 1,
                modelName: "old-model",
                provider: "openai",
                currentScore: 50,
                baselineScore: 70,
                dropPercentage: 20,
                severity: "warning",
                detectedAt: nil,
                message: "old-drop",
                type: "drift"
            )
        ]
        store.providerReliability = [
            ProviderReliabilityRow(
                provider: "openai",
                trustScore: 81,
                totalIncidents: 1,
                incidentsPerMonth: 1,
                avgRecoveryHours: "1.2",
                lastIncident: nil,
                trend: "reliable",
                isAvailable: true
            )
        ]

        await store.refreshNow(
            fetcher: .init(
                fetchScores: {
                    [self.makeScore(id: "new-score", provider: "openai", score: 72, status: .good)]
                },
                fetchGlobalIndex: {
                    self.makeGlobalIndex(score: 91)
                },
                fetchDashboardAlerts: {
                    throw StubError.failed
                },
                fetchBatchStatus: {
                    throw StubError.failed
                },
                fetchRecommendations: {
                    throw StubError.failed
                },
                fetchDegradations: {
                    throw StubError.failed
                },
                fetchProviderReliability: {
                    throw StubError.failed
                }
            )
        )

        XCTAssertEqual(store.scores.map(\.id), ["new-score"])
        XCTAssertEqual(store.globalIndex?.current.globalScore, 91)
        XCTAssertEqual(store.dashboardAlerts.map(\.name), ["old-alert"])
        XCTAssertEqual(store.batchStatus?.nextScheduledRun, "2026-04-11T18:00:00.000Z")
        XCTAssertEqual(store.recommendations?.bestForCode?.name, "gpt-old")
        XCTAssertEqual(store.degradations.map(\.modelName), ["old-model"])
        XCTAssertEqual(store.providerReliability.map(\.provider), ["openai"])
        XCTAssertNotNil(store.lastRefreshed)
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testLoadHoverDataIfNeededCachesResultAndDeduplicatesInflightRequests() async {
        let store = makeIsolatedStore(testName: #function)
        let counter = CallCounter()

        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { _ in
                await counter.recordDetail()
                try await Task.sleep(for: .milliseconds(40))
                return self.makeModelDetail()
            },
            fetchModelStats: { _ in
                await counter.recordStats()
                try await Task.sleep(for: .milliseconds(40))
                return self.makeModelStats()
            },
            fetchModelHistory: { _ in
                await counter.recordHistory()
                try await Task.sleep(for: .milliseconds(40))
                return self.makeModelHistory()
            }
        )

        async let first: Void = store.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)
        async let second: Void = store.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)
        _ = await (first, second)

        XCTAssertEqual(store.modelDetailsByID["38"]?.id, 38)
        XCTAssertEqual(store.modelStatsByModelID["38"]?.totalRuns, 7887)
        XCTAssertEqual(store.historyByModelID["38"]?.history.count, 1)
        XCTAssertTrue(store.hasResolvedHoverPayload(for: "38"))
        let firstCounts = await counter.snapshot()
        XCTAssertEqual(firstCounts.detail, 1)
        XCTAssertEqual(firstCounts.stats, 1)
        XCTAssertEqual(firstCounts.history, 1)

        await store.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)
        let secondCounts = await counter.snapshot()
        XCTAssertEqual(secondCounts.detail, 1)
        XCTAssertEqual(secondCounts.stats, 1)
        XCTAssertEqual(secondCounts.history, 1)
    }

    @MainActor
    func testLoadHoverDataIfNeededKeepsSuccessfulPartialDataWhenOneEndpointFails() async {
        let store = makeIsolatedStore(testName: #function)

        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { _ in self.makeModelDetail() },
            fetchModelStats: { _ in throw StubError.failed },
            fetchModelHistory: { _ in self.makeModelHistory() }
        )

        await store.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)

        XCTAssertEqual(store.modelDetailsByID["38"]?.id, 38)
        XCTAssertNil(store.modelStatsByModelID["38"])
        XCTAssertEqual(store.historyByModelID["38"]?.history.count, 1)
        XCTAssertTrue(store.hasResolvedHoverPayload(for: "38"))
    }

    @MainActor
    func testLoadHoverDataIfNeededReusesExistingHistoryCache() async {
        let store = makeIsolatedStore(testName: #function)
        let counter = CallCounter()
        store.historyByModelID["38"] = makeModelHistory()

        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { _ in
                await counter.recordDetail()
                return self.makeModelDetail()
            },
            fetchModelStats: { _ in
                await counter.recordStats()
                return self.makeModelStats()
            },
            fetchModelHistory: { _ in
                await counter.recordHistory()
                return self.makeModelHistory()
            }
        )

        await store.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)

        XCTAssertEqual(store.historyByModelID["38"]?.history.count, 1)
        let counts = await counter.snapshot()
        XCTAssertEqual(counts.detail, 1)
        XCTAssertEqual(counts.stats, 1)
        XCTAssertEqual(counts.history, 0)
    }

    @MainActor
    func testPrefetchHoverDataIfNeededWarmsRequestedVisibleModelsOnlyOnce() async {
        let store = makeIsolatedStore(testName: #function)
        let counter = ModelCallCounter()

        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { modelId in
                await counter.recordDetail(for: modelId)
                return self.makeModelDetail(id: Int(modelId) ?? 0)
            },
            fetchModelStats: { modelId in
                await counter.recordStats(for: modelId)
                return self.makeModelStats(modelId: Int(modelId) ?? 0)
            },
            fetchModelHistory: { modelId in
                await counter.recordHistory(for: modelId)
                return self.makeModelHistory(modelId: Int(modelId) ?? 0)
            }
        )

        await store.prefetchHoverDataIfNeeded(modelIDs: ["38", "57", "38"], fetcher: fetcher)

        XCTAssertEqual(store.modelDetailsByID["38"]?.id, 38)
        XCTAssertEqual(store.modelDetailsByID["57"]?.id, 57)
        XCTAssertNil(store.modelDetailsByID["99"])
        let firstDetail38 = await counter.detailCount(for: "38")
        let firstDetail57 = await counter.detailCount(for: "57")
        let firstStats38 = await counter.statsCount(for: "38")
        let firstHistory57 = await counter.historyCount(for: "57")
        XCTAssertEqual(firstDetail38, 1)
        XCTAssertEqual(firstDetail57, 1)
        XCTAssertEqual(firstStats38, 1)
        XCTAssertEqual(firstHistory57, 1)

        await store.prefetchHoverDataIfNeeded(modelIDs: ["57", "38"], fetcher: fetcher)

        let secondDetail38 = await counter.detailCount(for: "38")
        let secondDetail57 = await counter.detailCount(for: "57")
        let secondStats38 = await counter.statsCount(for: "38")
        let secondHistory57 = await counter.historyCount(for: "57")
        XCTAssertEqual(secondDetail38, 1)
        XCTAssertEqual(secondDetail57, 1)
        XCTAssertEqual(secondStats38, 1)
        XCTAssertEqual(secondHistory57, 1)
    }

    @MainActor
    func testPersistentHoverCacheSurvivesStoreRecreation() async {
        let defaults = makeIsolatedDefaults(testName: #function)

        let counter = ModelCallCounter()
        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { modelId in
                await counter.recordDetail(for: modelId)
                return self.makeModelDetail(id: Int(modelId) ?? 0)
            },
            fetchModelStats: { modelId in
                await counter.recordStats(for: modelId)
                return self.makeModelStats(modelId: Int(modelId) ?? 0)
            },
            fetchModelHistory: { modelId in
                await counter.recordHistory(for: modelId)
                return self.makeModelHistory(modelId: Int(modelId) ?? 0)
            }
        )

        let firstStore = AIStupidLevelStore(defaults: defaults)
        await firstStore.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)

        let firstDetailCalls = await counter.detailCount(for: "38")
        let firstStatsCalls = await counter.statsCount(for: "38")
        let firstHistoryCalls = await counter.historyCount(for: "38")
        XCTAssertEqual(firstDetailCalls, 1)
        XCTAssertEqual(firstStatsCalls, 1)
        XCTAssertEqual(firstHistoryCalls, 1)

        let secondStore = AIStupidLevelStore(defaults: defaults)
        XCTAssertTrue(secondStore.hasResolvedHoverPayload(for: "38"))
        XCTAssertEqual(secondStore.modelDetailsByID["38"]?.id, 38)
        XCTAssertEqual(secondStore.modelStatsByModelID["38"]?.modelId, 38)
        XCTAssertEqual(secondStore.historyByModelID["38"]?.modelId, 38)

        await secondStore.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)

        let secondDetailCalls = await counter.detailCount(for: "38")
        let secondStatsCalls = await counter.statsCount(for: "38")
        let secondHistoryCalls = await counter.historyCount(for: "38")
        XCTAssertEqual(secondDetailCalls, 1)
        XCTAssertEqual(secondStatsCalls, 1)
        XCTAssertEqual(secondHistoryCalls, 1)
    }

    @MainActor
    func testPersistentHoverCacheExpiresAfterTTL() async {
        let defaults = makeIsolatedDefaults(testName: #function)

        let cachedAt = Date(timeIntervalSince1970: 1_000)
        let expiredNow = cachedAt.addingTimeInterval(601)
        let counter = ModelCallCounter()
        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 0) },
            fetchDashboardAlerts: { [] },
            fetchBatchStatus: { DashboardBatchStatusData(isBatchInProgress: nil, schedulerRunning: nil, nextScheduledRun: nil) },
            fetchRecommendations: { AnalyticsRecommendationsPayload(bestForCode: nil, mostReliable: nil, fastestResponse: nil, avoidNow: []) },
            fetchDegradations: { [] },
            fetchProviderReliability: { [] },
            fetchModelDetail: { modelId in
                await counter.recordDetail(for: modelId)
                return self.makeModelDetail(id: Int(modelId) ?? 0)
            },
            fetchModelStats: { modelId in
                await counter.recordStats(for: modelId)
                return self.makeModelStats(modelId: Int(modelId) ?? 0)
            },
            fetchModelHistory: { modelId in
                await counter.recordHistory(for: modelId)
                return self.makeModelHistory(modelId: Int(modelId) ?? 0)
            }
        )

        let firstStore = AIStupidLevelStore(defaults: defaults, now: { cachedAt })
        await firstStore.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)

        let secondStore = AIStupidLevelStore(defaults: defaults, now: { expiredNow })
        XCTAssertFalse(secondStore.hasResolvedHoverPayload(for: "38"))

        await secondStore.loadHoverDataIfNeeded(modelId: "38", fetcher: fetcher)

        let detailCalls = await counter.detailCount(for: "38")
        let statsCalls = await counter.statsCount(for: "38")
        let historyCalls = await counter.historyCount(for: "38")
        XCTAssertEqual(detailCalls, 2)
        XCTAssertEqual(statsCalls, 2)
        XCTAssertEqual(historyCalls, 2)
    }

    @MainActor
    func testPersistentMainDashboardCacheSurvivesStoreRecreation() async {
        let defaults = makeIsolatedDefaults(testName: #function)

        let fetcher = AIStupidLevelStore.Fetcher(
            fetchScores: { [self.makeScore(id: "38", provider: "openai", score: 91, status: .good)] },
            fetchGlobalIndex: { self.makeGlobalIndex(score: 88) },
            fetchDashboardAlerts: {
                [DashboardAlert(name: "api", provider: "openai", issue: "Latency", severity: "warning", detectedAt: "2026-04-14T11:00:00Z")]
            },
            fetchBatchStatus: {
                DashboardBatchStatusData(
                    isBatchInProgress: false,
                    schedulerRunning: true,
                    nextScheduledRun: "2026-04-14T12:00:00Z"
                )
            },
            fetchRecommendations: {
                AnalyticsRecommendationsPayload(
                    bestForCode: AnalyticsRecommendationSlot(
                        id: "38",
                        name: "gpt-4.1",
                        vendor: "openai",
                        score: 91,
                        lastUpdate: "2026-04-14T11:00:00Z",
                        displayScore: 91,
                        rank: 1,
                        reason: "Best overall",
                        evidence: nil,
                        correctness: nil,
                        codeQuality: nil,
                        stabilityScore: nil
                    ),
                    mostReliable: nil,
                    fastestResponse: nil,
                    avoidNow: []
                )
            },
            fetchDegradations: {
                [AnalyticsDegradationItem(
                    modelId: 38,
                    modelName: "gpt-4.1",
                    provider: "openai",
                    currentScore: 91,
                    baselineScore: 95,
                    dropPercentage: 4,
                    severity: "warning",
                    detectedAt: "2026-04-14T11:00:00Z",
                    message: "Minor regression",
                    type: "drift"
                )]
            },
            fetchProviderReliability: {
                [ProviderReliabilityRow(
                    provider: "openai",
                    trustScore: 84,
                    totalIncidents: 2,
                    incidentsPerMonth: 1,
                    avgRecoveryHours: "0.5",
                    lastIncident: "2026-04-13T10:00:00Z",
                    trend: "stable",
                    isAvailable: true
                )]
            }
        )

        let firstStore = AIStupidLevelStore(defaults: defaults)
        await firstStore.refreshNow(fetcher: fetcher)

        let secondStore = AIStupidLevelStore(defaults: defaults)
        XCTAssertEqual(secondStore.scores.map(\.id), ["38"])
        XCTAssertEqual(secondStore.globalIndex?.current.globalScore, 88)
        XCTAssertEqual(secondStore.dashboardAlerts.map(\.name), ["api"])
        XCTAssertEqual(secondStore.batchStatus?.nextScheduledRun, "2026-04-14T12:00:00Z")
        XCTAssertEqual(secondStore.recommendations?.bestForCode?.name, "gpt-4.1")
        XCTAssertEqual(secondStore.degradations.map(\.modelId), [38])
        XCTAssertEqual(secondStore.providerReliability.map(\.provider), ["openai"])
    }

    private func makeScore(
        id: String,
        provider: String,
        score: Double,
        status: BenchmarkStatus
    ) -> BenchmarkScore {
        BenchmarkScore(
            id: id, name: "model-\(id)", provider: provider,
            currentScore: score, trend: .stable, status: status,
            confidenceLower: nil, confidenceUpper: nil, standardError: nil,
            isStale: false, lastUpdated: nil
        )
    }

    private func makeGlobalIndex(score: Double) -> GlobalIndex {
        GlobalIndex(
            current: GlobalIndexPoint(
                timestamp: "2026-04-11T04:58:40.355Z",
                label: "Current",
                globalScore: score,
                modelsCount: 132,
                hoursAgo: 0
            ),
            history: [
                GlobalIndexPoint(
                    timestamp: "2026-04-11T04:58:40.355Z",
                    label: "Current",
                    globalScore: score,
                    modelsCount: 132,
                    hoursAgo: 0
                )
            ],
            trend: "stable",
            performingWell: 2,
            totalModels: 22,
            lastUpdated: "2026-04-11T04:58:43.775Z"
        )
    }

    private func makeModelDetail(id: Int = 38) -> BenchmarkModelDetail {
        BenchmarkModelDetail(
            id: id,
            name: "model-\(id)",
            vendor: "anthropic",
            version: "2025-08-05",
            notes: "Claude Opus 4.1 - most powerful",
            createdAt: "2024-01-01T00:00:00.000Z",
            displayName: nil,
            showInRankings: true,
            supportsToolCalling: false,
            maxToolsPerCall: 10,
            toolCallReliability: 0,
            usesReasoningEffort: false,
            latestScore: BenchmarkModelLatestScore(
                id: 117257,
                modelId: 38,
                ts: "2026-04-13T10:00:35.465Z",
                stupidScore: 76,
                axes: BenchmarkModelAxes(
                    correctness: 1,
                    spec: 0.8613038520844984,
                    complexity: nil,
                    codeQuality: 0.8344508381718067,
                    efficiency: 0.6566467159075685,
                    stability: 1,
                    refusal: 1,
                    edgeCases: nil,
                    recovery: 1,
                    debugging: nil,
                    format: nil,
                    safety: nil
                ),
                cusum: 0,
                note: nil,
                suite: "hourly",
                confidenceLower: nil,
                confidenceUpper: nil,
                standardError: nil,
                sampleSize: 5,
                modelVariance: nil,
                displayScore: 76
            )
        )
    }

    private func makeModelStats(modelId: Int = 38) -> BenchmarkModelStats {
        BenchmarkModelStats(
            modelId: modelId,
            currentScore: 66,
            totalRuns: 7887,
            successfulRuns: 7779,
            successRate: 99,
            averageCorrectness: 0.9807955123315535,
            averageLatency: 4548.451756054266,
            debug: BenchmarkModelStatsDebug(
                period: "latest",
                sortBy: "combined",
                suite: "hourly",
                calculationMethod: "combined-average"
            )
        )
    }

    private func makeModelHistory(modelId: Int = 38) -> ModelHistoryPayload {
        ModelHistoryPayload(
            modelId: modelId,
            period: "latest",
            sortBy: "combined",
            dataPoints: 1,
            timeRange: nil,
            history: [
                ModelHistoryPoint(
                    timestamp: "2026-04-13T10:00:35.465Z",
                    stupidScore: 76,
                    displayScore: 76
                )
            ]
        )
    }

    @MainActor
    private func makeIsolatedStore(testName: String) -> AIStupidLevelStore {
        let defaults = makeIsolatedDefaults(testName: testName)
        return AIStupidLevelStore(defaults: defaults)
    }

    private func makeIsolatedDefaults(testName: String) -> UserDefaults {
        let suiteName = "AIStupidLevelStoreTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
