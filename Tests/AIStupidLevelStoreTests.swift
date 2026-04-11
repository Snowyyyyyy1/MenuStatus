import XCTest
@testable import MenuStatus

final class AIStupidLevelStoreTests: XCTestCase {
    func testVendorSummaryFiltersAndSortsByScore() {
        let scores = [
            makeScore(id: "1", provider: "anthropic", score: 62, status: .good),
            makeScore(id: "2", provider: "anthropic", score: 71, status: .good),
            makeScore(id: "3", provider: "openai", score: 65, status: .warning),
            makeScore(id: "4", provider: "anthropic", score: 58, status: .critical),
        ]

        let summary = BenchmarkVendorSummary.build(from: scores, vendor: "anthropic")

        XCTAssertEqual(summary.scores.map(\.id), ["2", "1", "4"])
        XCTAssertEqual(summary.averageScore, (71 + 62 + 58) / 3.0, accuracy: 0.01)
        XCTAssertEqual(summary.warningCount, 0)
        XCTAssertEqual(summary.criticalCount, 1)
    }

    func testVendorMatchingIsCaseInsensitive() {
        let scores = [makeScore(id: "1", provider: "OpenAI", score: 70, status: .good)]
        let summary = BenchmarkVendorSummary.build(from: scores, vendor: "openai")
        XCTAssertEqual(summary.scores.count, 1)
    }

    func testEmptyVendorSummary() {
        let summary = BenchmarkVendorSummary.build(from: [], vendor: "xai")
        XCTAssertTrue(summary.isEmpty)
        XCTAssertEqual(summary.averageScore, 0)
    }

    @MainActor
    func testStoreSummaryForVendorReturnsMatching() {
        let store = AIStupidLevelStore()
        store.scores = [
            makeScore(id: "1", provider: "anthropic", score: 70, status: .good),
            makeScore(id: "2", provider: "xai", score: 55, status: .warning),
        ]

        XCTAssertEqual(store.summary(forVendor: "anthropic").scores.count, 1)
        XCTAssertEqual(store.summary(forVendor: "xai").scores.count, 1)
        XCTAssertTrue(store.summary(forVendor: "google").isEmpty)
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
}
