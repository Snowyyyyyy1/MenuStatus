import XCTest
@testable import MenuStatus

final class AIStupidLevelClientTests: XCTestCase {
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
}
