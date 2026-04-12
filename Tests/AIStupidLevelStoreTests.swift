import XCTest
@testable import MenuStatus

final class AIStupidLevelStoreTests: XCTestCase {
    private enum StubError: Error {
        case failed
    }

    @MainActor
    func testHasVisibleContentReflectsLoadedBenchmarkSections() {
        let store = AIStupidLevelStore()
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
    func testRefreshNowKeepsLastSuccessfulOptionalDataOnFailure() async {
        let store = AIStupidLevelStore()
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
}
