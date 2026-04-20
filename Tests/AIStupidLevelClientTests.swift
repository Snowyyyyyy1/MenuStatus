import XCTest
@testable import MenuStatus

final class AIStupidLevelClientTests: XCTestCase {
    func testModelDetailPageURLUsesModelIDPath() {
        XCTAssertEqual(
            AIStupidLevelClient.modelDetailPageURL(modelId: "38")?.absoluteString,
            "https://aistupidlevel.info/models/38"
        )
    }

    func testParseDashboardScoresResponse() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "id": "40",
              "name": "claude-sonnet-4-20250514",
              "provider": "anthropic",
              "currentScore": 71,
              "trend": "up",
              "status": "good",
              "confidenceLower": 46.3,
              "confidenceUpper": 83.3,
              "standardError": 6.7,
              "isStale": false,
              "lastUpdated": "2026-04-11T04:00:00.023Z"
            },
            {
              "id": "230",
              "name": "gpt-5.4",
              "provider": "openai",
              "currentScore": 65,
              "trend": "down",
              "status": "warning",
              "confidenceLower": 49.1,
              "confidenceUpper": 87.3,
              "standardError": 6.9,
              "isStale": false,
              "lastUpdated": "2026-04-11T04:00:00.023Z"
            }
          ]
        }
        """

        let decoded = try AIStupidLevelClient.decodeScores(Data(json.utf8))

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].id, "40")
        XCTAssertEqual(decoded[0].provider, "anthropic")
        XCTAssertEqual(decoded[0].currentScore, 71)
        XCTAssertEqual(decoded[0].trend, .up)
        XCTAssertEqual(decoded[0].status, .good)
        XCTAssertEqual(decoded[1].trend, .down)
        XCTAssertEqual(decoded[1].status, .warning)
    }

    func testParseDashboardScoresResponseDecodesLossyCurrentScoreValues() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "id": "1",
              "name": "numeric-score",
              "provider": "openai",
              "currentScore": 71,
              "trend": "stable",
              "status": "good"
            },
            {
              "id": "2",
              "name": "string-score",
              "provider": "anthropic",
              "currentScore": "65",
              "trend": "up",
              "status": "warning"
            },
            {
              "id": "3",
              "name": "nil-score",
              "provider": "x",
              "currentScore": null,
              "trend": "down",
              "status": "critical"
            },
            {
              "id": "4",
              "name": "empty-score",
              "provider": "y",
              "currentScore": "",
              "trend": "stable",
              "status": "unknown"
            },
            {
              "id": "5",
              "name": "unavailable-score",
              "provider": "z",
              "currentScore": "unavailable",
              "trend": "stable",
              "status": "good"
            }
          ]
        }
        """

        let decoded = try AIStupidLevelClient.decodeScores(Data(json.utf8))

        XCTAssertEqual(decoded.map(\.currentScore), [71, 65, nil, nil, nil])
    }

    func testParseDashboardScoresResponseTreatsNonFiniteCurrentScoresAsNil() throws {
        let json = """
        {
          "success": true,
          "data": [
            { "id": "1", "name": "nan-score", "provider": "openai", "currentScore": "nan", "trend": "stable", "status": "good" },
            { "id": "2", "name": "pos-inf-score", "provider": "openai", "currentScore": "inf", "trend": "stable", "status": "good" },
            { "id": "3", "name": "neg-inf-score", "provider": "openai", "currentScore": "-inf", "trend": "stable", "status": "good" }
          ]
        }
        """

        let decoded = try AIStupidLevelClient.decodeScores(Data(json.utf8))

        XCTAssertEqual(decoded.map(\.currentScore), [nil, nil, nil])
    }

    func testUnknownTrendDefaultsToStable() throws {
        let json = """
        {"success":true,"data":[{"id":"1","name":"m","provider":"x","currentScore":50,"trend":"sideways","status":"good"}]}
        """
        let decoded = try AIStupidLevelClient.decodeScores(Data(json.utf8))
        XCTAssertEqual(decoded[0].trend, .stable)
    }

    func testParseGlobalIndexResponse() throws {
        let json = """
        {
          "success": true,
          "data": {
            "current": { "timestamp": "2026-04-11T04:58:40.355Z", "label": "Current", "globalScore": 84, "modelsCount": 132, "hoursAgo": 0 },
            "history": [
              { "timestamp": "2026-04-11T04:58:40.355Z", "label": "Current", "globalScore": 84, "modelsCount": 132, "hoursAgo": 0 },
              { "timestamp": "2026-04-10T22:58:40.355Z", "label": "6h ago", "globalScore": 87, "modelsCount": 132, "hoursAgo": 6 }
            ],
            "trend": "declining",
            "performingWell": 2,
            "totalModels": 22,
            "lastUpdated": "2026-04-11T04:58:43.775Z"
          }
        }
        """

        let decoded = try AIStupidLevelClient.decodeGlobalIndex(Data(json.utf8))

        XCTAssertEqual(decoded.current.globalScore, 84)
        XCTAssertEqual(decoded.history.count, 2)
        XCTAssertEqual(decoded.trend, "declining")
    }

    func testParseGlobalIndexResponseDecodesLossyGlobalScoreValues() throws {
        let json = """
        {
          "success": true,
          "data": {
            "current": { "timestamp": "2026-04-11T04:58:40.355Z", "label": "Current", "globalScore": "84", "modelsCount": 132, "hoursAgo": 0 },
            "history": [
              { "timestamp": "2026-04-11T04:58:40.355Z", "label": "Current", "globalScore": null, "modelsCount": 132, "hoursAgo": 0 },
              { "timestamp": "2026-04-10T22:58:40.355Z", "label": "6h ago", "globalScore": "", "modelsCount": 132, "hoursAgo": 6 },
              { "timestamp": "2026-04-10T16:58:40.355Z", "label": "12h ago", "globalScore": "unavailable", "modelsCount": 132, "hoursAgo": 12 }
            ],
            "trend": "declining",
            "performingWell": 2,
            "totalModels": 22,
            "lastUpdated": "2026-04-11T04:58:43.775Z"
          }
        }
        """

        let decoded = try AIStupidLevelClient.decodeGlobalIndex(Data(json.utf8))

        XCTAssertEqual(decoded.current.globalScore, 84)
        XCTAssertEqual(decoded.history.map(\.globalScore), [nil, nil, nil])
        XCTAssertEqual(decoded.trend, "declining")
    }

    func testRankingSortOrdersNumericScoresFirstWithDeterministicTies() {
        let sorted = BenchmarkPresentationLogic.sortedScoresForRanking([
            makeScore(id: "c", name: "zeta", provider: "openai", score: 91),
            makeScore(id: "a", name: "alpha", provider: "anthropic", score: 91),
            makeScore(id: "b", name: "beta", provider: "anthropic", score: 72),
            makeScore(id: "n", name: "nil", provider: "x", score: nil)
        ])

        XCTAssertEqual(sorted.map(\.id), ["a", "c", "b", "n"])
    }

    func testVendorSummaryCountsAllMatchesAndAveragesNumericScoresOnly() {
        let scores = [
            makeScore(id: "1", name: "alpha", provider: "openai", score: 90),
            makeScore(id: "2", name: "beta", provider: "openai", score: nil),
            makeScore(id: "3", name: "gamma", provider: "openai", score: 50),
            makeScore(id: "4", name: "delta", provider: "anthropic", score: 80)
        ]

        let summary = BenchmarkPresentationLogic.vendorSummary(for: "openai", scores: scores)

        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.averageScore, 70)
    }

    func testVendorSummaryReturnsNilAverageWhenNoNumericScoresExist() {
        let scores = [
            makeScore(id: "1", name: "alpha", provider: "openai", score: nil),
            makeScore(id: "2", name: "beta", provider: "openai", score: nil)
        ]

        let summary = BenchmarkPresentationLogic.vendorSummary(for: "openai", scores: scores)

        XCTAssertEqual(summary.count, 2)
        XCTAssertNil(summary.averageScore)
    }

    func testDecodeDashboardAlerts() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "name": "gpt-5.4",
              "provider": "openai",
              "issue": "benchmark drift detected",
              "severity": "warning",
              "detectedAt": "2026-04-11T15:00:00.039Z"
            }
          ]
        }
        """
        let decoded = try AIStupidLevelClient.decodeDashboardAlerts(Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].provider, "openai")
        XCTAssertEqual(decoded[0].severity, "warning")
    }

    func testDecodeBatchStatus() throws {
        let json = """
        {
          "success": true,
          "data": {
            "isBatchInProgress": false,
            "schedulerRunning": true,
            "nextScheduledRun": "2026-04-11T18:00:00.000Z"
          }
        }
        """
        let decoded = try AIStupidLevelClient.decodeBatchStatus(Data(json.utf8))
        XCTAssertEqual(decoded.schedulerRunning, true)
        XCTAssertEqual(decoded.nextScheduledRun, "2026-04-11T18:00:00.000Z")
    }

    func testDecodeRecommendations() throws {
        let json = """
        {
          "success": true,
          "data": {
            "bestForCode": {
              "id": "204",
              "name": "gpt-5.2",
              "vendor": "openai",
              "score": 68,
              "rank": 1,
              "reason": "Ranked #1"
            },
            "mostReliable": null,
            "fastestResponse": null,
            "avoidNow": []
          }
        }
        """
        let decoded = try AIStupidLevelClient.decodeRecommendations(Data(json.utf8))
        XCTAssertEqual(decoded.bestForCode?.name, "gpt-5.2")
        XCTAssertEqual(decoded.bestForCode?.vendor, "openai")
    }

    func testDecodeDegradations() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "modelId": 165,
              "modelName": "glm-4.6",
              "provider": "glm",
              "currentScore": 40,
              "baselineScore": 65,
              "dropPercentage": 38,
              "severity": "critical",
              "detectedAt": "2026-04-11T16:05:41.072Z",
              "message": "Critical performance",
              "type": "critical_failure"
            }
          ]
        }
        """
        let decoded = try AIStupidLevelClient.decodeDegradations(Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].modelId, 165)
        XCTAssertEqual(decoded[0].provider, "glm")
    }

    func testDecodeProviderReliability() throws {
        let json = """
        {
          "success": true,
          "data": [
            {
              "provider": "openai",
              "trustScore": 81,
              "totalIncidents": 1,
              "avgRecoveryHours": "1.2",
              "trend": "reliable",
              "isAvailable": true
            }
          ],
          "timestamp": "2026-04-11T16:14:21.944Z"
        }
        """
        let decoded = try AIStupidLevelClient.decodeProviderReliability(Data(json.utf8))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].provider, "openai")
        XCTAssertEqual(decoded[0].trustScore, 81)
    }

    func testDecodeModelHistory() throws {
        let json = """
        {
          "modelId": 38,
          "period": "30 days",
          "sortBy": "combined",
          "dataPoints": 2,
          "timeRange": "30d",
          "history": [
            {
              "timestamp": "2026-04-11T15:00:00.039Z",
              "stupidScore": 74,
              "displayScore": 74
            }
          ]
        }
        """
        let decoded = try AIStupidLevelClient.decodeModelHistory(Data(json.utf8))
        XCTAssertEqual(decoded.modelId, 38)
        XCTAssertEqual(decoded.history.count, 1)
        XCTAssertEqual(decoded.history[0].stupidScore, 74)
    }

    func testDecodeModelDetail() throws {
        let json = """
        {
          "id": 38,
          "name": "claude-opus-4-1-20250805",
          "vendor": "anthropic",
          "version": "2025-08-05",
          "notes": "Claude Opus 4.1 - most powerful",
          "createdAt": "2024-01-01T00:00:00.000Z",
          "displayName": null,
          "showInRankings": true,
          "supportsToolCalling": false,
          "maxToolsPerCall": 10,
          "toolCallReliability": 0,
          "usesReasoningEffort": false,
          "latestScore": {
            "id": 117257,
            "modelId": 38,
            "ts": "2026-04-13T10:00:35.465Z",
            "stupidScore": 76,
            "axes": {
              "correctness": 1,
              "spec": 0.8613038520844984,
              "codeQuality": 0.8344508381718067,
              "efficiency": 0.6566467159075685,
              "stability": 1,
              "refusal": 1,
              "recovery": 1
            },
            "suite": "hourly",
            "displayScore": 76,
            "sampleSize": 5
          }
        }
        """

        let decoded = try AIStupidLevelClient.decodeModelDetail(Data(json.utf8))
        XCTAssertEqual(decoded.id, 38)
        XCTAssertEqual(decoded.name, "claude-opus-4-1-20250805")
        XCTAssertEqual(decoded.vendor, "anthropic")
        XCTAssertEqual(decoded.version, "2025-08-05")
        XCTAssertEqual(decoded.notes, "Claude Opus 4.1 - most powerful")
        XCTAssertEqual(decoded.supportsToolCalling, false)
        XCTAssertEqual(decoded.maxToolsPerCall, 10)
        XCTAssertEqual(decoded.usesReasoningEffort, false)
        XCTAssertEqual(decoded.latestScore?.displayScore, 76)
        XCTAssertEqual(decoded.latestScore?.sampleSize, 5)
    }

    func testDecodeModelStats() throws {
        let json = """
        {
          "modelId": 38,
          "currentScore": 66,
          "totalRuns": 7887,
          "successfulRuns": 7779,
          "successRate": 99,
          "averageCorrectness": 0.9807955123315535,
          "averageLatency": 4548.451756054266,
          "debug": {
            "period": "latest",
            "sortBy": "combined",
            "suite": "hourly",
            "calculationMethod": "combined-average"
          }
        }
        """

        let decoded = try AIStupidLevelClient.decodeModelStats(Data(json.utf8))
        XCTAssertEqual(decoded.modelId, 38)
        XCTAssertEqual(decoded.currentScore, 66)
        XCTAssertEqual(decoded.totalRuns, 7887)
        XCTAssertEqual(decoded.successfulRuns, 7779)
        XCTAssertEqual(decoded.successRate, 99)
        XCTAssertEqual(decoded.averageCorrectness, 0.9807955123315535)
        XCTAssertEqual(decoded.averageLatency, 4548.451756054266)
        XCTAssertEqual(decoded.debug?.period, "latest")
        XCTAssertEqual(decoded.debug?.sortBy, "combined")
    }

    private func makeScore(id: String, name: String, provider: String, score: Double?) -> BenchmarkScore {
        BenchmarkScore(
            id: id,
            name: name,
            provider: provider,
            currentScore: score,
            trend: .stable,
            status: .good,
            confidenceLower: nil,
            confidenceUpper: nil,
            standardError: nil,
            isStale: nil,
            lastUpdated: nil
        )
    }
}
