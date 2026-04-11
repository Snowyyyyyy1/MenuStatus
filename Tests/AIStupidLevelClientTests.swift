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
}
