# AI Stupid Level Integration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate aistupidlevel.info benchmark data into MenuStatus by weaving per-vendor model scores into each existing provider tab, plus a global "AI stupidity index" bar at the top of the menu popover.

**Architecture:** A new `AIStupidLevelStore` (`@Observable`) runs in parallel with the existing `StatusStore`, polling `https://aistupidlevel.info/api/dashboard/scores` and `/api/dashboard/global-index`. A new optional `aiStupidLevelVendor: String?` field on `ProviderConfig` marks which AI vendor a provider represents; if set, its tab content appends a collapsible Model Benchmarks section filtered to that vendor. A new `StatusPlatform.aiStupidLevelOnly` case supports "benchmark-only" providers (xAI/Google/Kimi/GLM/DeepSeek) that have no status page — for these, the tab renders only the benchmark section. Built-in providers are now removable via a new `SettingsStore.removedBuiltInIDs` set, with a "Reset built-in providers" button in Settings.

**Tech Stack:** Swift 5.9+, SwiftUI, `@Observable`, `URLSession`, XCTest. No new dependencies.

---

## File Structure

**New files:**
- `Sources/AIStupidLevelModels.swift` — Codable types for the API (BenchmarkScore, GlobalIndex, etc.) and derived presentation types (BenchmarkSummary)
- `Sources/AIStupidLevelClient.swift` — Stateless fetcher with typed decode
- `Sources/AIStupidLevelStore.swift` — `@Observable` store with polling, vendor grouping, error state
- `Sources/BenchmarkViews.swift` — `GlobalIndexBar`, `BenchmarkSection`, `BenchmarkModelRow`
- `Tests/AIStupidLevelClientTests.swift` — JSON parsing tests
- `Tests/AIStupidLevelStoreTests.swift` — Grouping / derive logic tests

**Modified files:**
- `Sources/StatusModels.swift` — Add `aiStupidLevelVendor: String?` to `ProviderConfig`; add `.aiStupidLevelOnly` to `StatusPlatform`; extend `builtInProviders` with the 5 benchmark-only vendors; set vendor slugs on existing `.openAI` / `.anthropic`
- `Sources/SettingsStore.swift` — Add `removedBuiltInIDs: Set<String>` and `benchmarkSectionExpanded: Set<String>`
- `Sources/ProviderConfigStore.swift` — Filter removed built-ins during load; `removeProvider` moves built-ins to `removedBuiltInIDs`; add `resetBuiltInProviders(settings:)`
- `Sources/StatusStore.swift` — Skip `.aiStupidLevelOnly` providers in `fetchAllProviderData` so no status-page requests fire for them
- `Sources/MenuStatusApp.swift` — Instantiate `AIStupidLevelStore`, start/stop polling, inject into views
- `Sources/StatusMenuContentView.swift` — Add `GlobalIndexBar` between tab grid and content; pass benchmark store down
- `Sources/StatusRowViews.swift` — `ProviderSectionView` appends `BenchmarkSection` if `provider.aiStupidLevelVendor != nil`; when `platform == .aiStupidLevelOnly`, render only a benchmark-only variant
- `Sources/SettingsView.swift` — Add "Reset built-in providers" button under the providers list

---

## Task 1: Benchmark API Models

**Files:**
- Create: `Sources/AIStupidLevelModels.swift`
- Test: `Tests/AIStupidLevelClientTests.swift` (created here, populated in Task 2)

- [ ] **Step 1: Create the models file**

```swift
// Sources/AIStupidLevelModels.swift
import Foundation
import SwiftUI

// MARK: - Raw API Types

/// GET /api/dashboard/scores → { success, data: [BenchmarkScore] }
struct BenchmarkScoresResponse: Decodable {
    let success: Bool
    let data: [BenchmarkScore]
}

struct BenchmarkScore: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let provider: String          // "anthropic", "openai", "xai", "google", "kimi", "glm", "deepseek", ...
    let currentScore: Double
    let trend: BenchmarkTrend
    let status: BenchmarkStatus
    let confidenceLower: Double?
    let confidenceUpper: Double?
    let standardError: Double?
    let isStale: Bool?
    let lastUpdated: String?

    // "score" is an alias field the server also returns; ignore by using custom keys
    private enum CodingKeys: String, CodingKey {
        case id, name, provider, currentScore, trend, status
        case confidenceLower, confidenceUpper, standardError, isStale, lastUpdated
    }
}

enum BenchmarkTrend: String, Decodable {
    case up, down, stable
    // Unknown values decode to .stable (defensive — server may add new values)
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BenchmarkTrend(rawValue: raw) ?? .stable
    }

    var symbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .stable: "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .up: .green
        case .down: .red
        case .stable: .secondary
        }
    }
}

enum BenchmarkStatus: String, Decodable {
    case good, warning, critical, unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BenchmarkStatus(rawValue: raw) ?? .unknown
    }

    var color: Color {
        switch self {
        case .good: .green
        case .warning: .yellow
        case .critical: .red
        case .unknown: .secondary
        }
    }
}

/// GET /api/dashboard/global-index → { success, data: { current, history, trend, ... } }
struct GlobalIndexResponse: Decodable {
    let success: Bool
    let data: GlobalIndex
}

struct GlobalIndex: Decodable {
    let current: GlobalIndexPoint
    let history: [GlobalIndexPoint]
    let trend: String            // "declining" | "stable" | "improving"
    let performingWell: Int?
    let totalModels: Int?
    let lastUpdated: String?
}

struct GlobalIndexPoint: Decodable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let label: String
    let globalScore: Double
    let modelsCount: Int?
    let hoursAgo: Int
}

// MARK: - Presentation Types

/// Derived per-vendor summary used by the UI.
struct BenchmarkVendorSummary: Equatable {
    let vendor: String
    let scores: [BenchmarkScore]    // Already sorted descending by currentScore
    let averageScore: Double
    let warningCount: Int
    let criticalCount: Int

    static func build(from scores: [BenchmarkScore], vendor: String) -> BenchmarkVendorSummary {
        let matching = scores
            .filter { $0.provider.caseInsensitiveCompare(vendor) == .orderedSame }
            .sorted { $0.currentScore > $1.currentScore }
        let avg: Double = matching.isEmpty
            ? 0
            : matching.map(\.currentScore).reduce(0, +) / Double(matching.count)
        return BenchmarkVendorSummary(
            vendor: vendor,
            scores: matching,
            averageScore: avg,
            warningCount: matching.filter { $0.status == .warning }.count,
            criticalCount: matching.filter { $0.status == .critical }.count
        )
    }

    var isEmpty: Bool { scores.isEmpty }
}
```

- [ ] **Step 2: Create empty test file so the test target compiles**

```swift
// Tests/AIStupidLevelClientTests.swift
import XCTest
@testable import MenuStatus

final class AIStupidLevelClientTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true)  // Populated in Task 2
    }
}
```

- [ ] **Step 3: Build to verify types compile**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/AIStupidLevelModels.swift Tests/AIStupidLevelClientTests.swift
git commit -m "feat: add AI Stupid Level benchmark models"
```

---

## Task 2: Benchmark Client + Parsing Tests

**Files:**
- Create: `Sources/AIStupidLevelClient.swift`
- Modify: `Tests/AIStupidLevelClientTests.swift`

- [ ] **Step 1: Write failing tests first**

Replace the placeholder in `Tests/AIStupidLevelClientTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: Compile failure — `AIStupidLevelClient` doesn't exist.

- [ ] **Step 3: Create the client**

```swift
// Sources/AIStupidLevelClient.swift
import Foundation

enum AIStupidLevelClientError: LocalizedError {
    case httpFailure(Int)
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .httpFailure(let code): "HTTP \(code)"
        case .apiFailure(let msg): msg
        }
    }
}

struct AIStupidLevelClient {
    static let baseURL = URL(string: "https://aistupidlevel.info")!

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // API already returns camelCase, no conversion needed
        return d
    }()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    static func fetchScores() async throws -> [BenchmarkScore] {
        let data = try await fetchData(path: "/api/dashboard/scores")
        return try decodeScores(data)
    }

    static func fetchGlobalIndex() async throws -> GlobalIndex {
        let data = try await fetchData(path: "/api/dashboard/global-index")
        return try decodeGlobalIndex(data)
    }

    /// Exposed for testing.
    static func decodeScores(_ data: Data) throws -> [BenchmarkScore] {
        let response = try decoder.decode(BenchmarkScoresResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("scores response success=false") }
        return response.data
    }

    /// Exposed for testing.
    static func decodeGlobalIndex(_ data: Data) throws -> GlobalIndex {
        let response = try decoder.decode(GlobalIndexResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("global-index response success=false") }
        return response.data
    }

    private static func fetchData(path: String) async throws -> Data {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw AIStupidLevelClientError.httpFailure(-1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw AIStupidLevelClientError.httpFailure(http.statusCode)
        }
        return data
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build -only-testing:MenuStatusTests/AIStupidLevelClientTests`
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIStupidLevelClient.swift Tests/AIStupidLevelClientTests.swift
git commit -m "feat: add AI Stupid Level API client with decode tests"
```

---

## Task 3: Benchmark Store with Vendor Grouping Tests

**Files:**
- Create: `Sources/AIStupidLevelStore.swift`
- Create: `Tests/AIStupidLevelStoreTests.swift`

- [ ] **Step 1: Write failing tests first**

```swift
// Tests/AIStupidLevelStoreTests.swift
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
```

- [ ] **Step 2: Run tests to verify failure**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build -only-testing:MenuStatusTests/AIStupidLevelStoreTests`
Expected: Compile failure — `AIStupidLevelStore` doesn't exist.

- [ ] **Step 3: Create the store**

```swift
// Sources/AIStupidLevelStore.swift
import Foundation
import Observation

@MainActor
@Observable
final class AIStupidLevelStore {
    var scores: [BenchmarkScore] = []
    var globalIndex: GlobalIndex?
    var lastRefreshed: Date?
    var isLoading = false
    var errorMessage: String?

    private var pollingTask: Task<Void, Never>?
    private(set) var pollInterval: TimeInterval = 300  // 5 min — benchmarks run hourly, no need to poll faster

    /// Start polling. Safe to call multiple times.
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
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        async let scoresTask = AIStupidLevelClient.fetchScores()
        async let globalTask = AIStupidLevelClient.fetchGlobalIndex()

        do {
            let fetchedScores = try await scoresTask
            self.scores = fetchedScores
        } catch {
            errorMessage = "Benchmark scores: \(error.localizedDescription)"
        }

        do {
            let fetchedIndex = try await globalTask
            self.globalIndex = fetchedIndex
        } catch {
            // Keep existing globalIndex if refresh fails
            if errorMessage == nil {
                errorMessage = "Global index: \(error.localizedDescription)"
            }
        }

        lastRefreshed = Date()
        isLoading = false
    }

    func summary(forVendor vendor: String) -> BenchmarkVendorSummary {
        BenchmarkVendorSummary.build(from: scores, vendor: vendor)
    }

    /// Whether any score in memory matches any of the provided vendor slugs.
    func hasAnyData(forVendors vendors: Set<String>) -> Bool {
        let lowered = Set(vendors.map { $0.lowercased() })
        return scores.contains { lowered.contains($0.provider.lowercased()) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build -only-testing:MenuStatusTests/AIStupidLevelStoreTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AIStupidLevelStore.swift Tests/AIStupidLevelStoreTests.swift
git commit -m "feat: add AIStupidLevelStore with vendor grouping"
```

---

## Task 4: Extend ProviderConfig with Benchmark Vendor Field

**Files:**
- Modify: `Sources/StatusModels.swift:27-58`

- [ ] **Step 1: Add new platform case and vendor field**

In `Sources/StatusModels.swift`, replace the current `enum StatusPlatform` and `struct ProviderConfig` + extension with:

```swift
enum StatusPlatform: String, Codable {
    case atlassianStatuspage
    case incidentIO
    case aiStupidLevelOnly  // Benchmark-only provider — no status page to scrape
}

struct ProviderConfig: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var baseURL: URL
    var platform: StatusPlatform
    var isBuiltIn: Bool
    var aiStupidLevelVendor: String?  // nil = no benchmark section

    var apiURL: URL { baseURL.appendingPathComponent("api/v2/summary.json") }
    var statusPageURL: URL { baseURL }

    var hasStatusPage: Bool { platform != .aiStupidLevelOnly }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    // Manual Codable so aiStupidLevelVendor decodes as nil when absent from old on-disk JSON
    private enum CodingKeys: String, CodingKey {
        case id, displayName, baseURL, platform, isBuiltIn, aiStupidLevelVendor
    }

    init(
        id: String,
        displayName: String,
        baseURL: URL,
        platform: StatusPlatform,
        isBuiltIn: Bool,
        aiStupidLevelVendor: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.platform = platform
        self.isBuiltIn = isBuiltIn
        self.aiStupidLevelVendor = aiStupidLevelVendor
    }
}

extension ProviderConfig {
    static let openAI = ProviderConfig(
        id: "openai", displayName: "OpenAI",
        baseURL: URL(string: "https://status.openai.com")!,
        platform: .incidentIO, isBuiltIn: true,
        aiStupidLevelVendor: "openai"
    )
    static let anthropic = ProviderConfig(
        id: "anthropic", displayName: "Claude",
        baseURL: URL(string: "https://status.claude.com")!,
        platform: .atlassianStatuspage, isBuiltIn: true,
        aiStupidLevelVendor: "anthropic"
    )

    // Benchmark-only built-ins. baseURL is a harmless placeholder — never fetched.
    private static let benchmarkPlaceholder = URL(string: "https://aistupidlevel.info")!

    static let xai = ProviderConfig(
        id: "xai-benchmark", displayName: "xAI",
        baseURL: benchmarkPlaceholder,
        platform: .aiStupidLevelOnly, isBuiltIn: true,
        aiStupidLevelVendor: "xai"
    )
    static let googleAI = ProviderConfig(
        id: "google-benchmark", displayName: "Google AI",
        baseURL: benchmarkPlaceholder,
        platform: .aiStupidLevelOnly, isBuiltIn: true,
        aiStupidLevelVendor: "google"
    )
    static let kimi = ProviderConfig(
        id: "kimi-benchmark", displayName: "Kimi",
        baseURL: benchmarkPlaceholder,
        platform: .aiStupidLevelOnly, isBuiltIn: true,
        aiStupidLevelVendor: "kimi"
    )
    static let glm = ProviderConfig(
        id: "glm-benchmark", displayName: "GLM",
        baseURL: benchmarkPlaceholder,
        platform: .aiStupidLevelOnly, isBuiltIn: true,
        aiStupidLevelVendor: "glm"
    )
    static let deepSeek = ProviderConfig(
        id: "deepseek-benchmark", displayName: "DeepSeek",
        baseURL: benchmarkPlaceholder,
        platform: .aiStupidLevelOnly, isBuiltIn: true,
        aiStupidLevelVendor: "deepseek"
    )

    static let builtInProviders: [ProviderConfig] = [
        .openAI, .anthropic, .xai, .googleAI, .kimi, .glm, .deepSeek,
    ]
}
```

- [ ] **Step 2: Build to verify compile**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run existing tests to ensure no regression**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusModels.swift
git commit -m "feat: add aiStupidLevelVendor to ProviderConfig + 5 benchmark vendors"
```

---

## Task 5: Removable Built-ins + Reset

**Files:**
- Modify: `Sources/SettingsStore.swift`
- Modify: `Sources/ProviderConfigStore.swift`

- [ ] **Step 1: Add `removedBuiltInIDs` and `benchmarkSectionExpanded` to SettingsStore**

In `Sources/SettingsStore.swift`, after the `providerOrder` property (around line 41), add:

```swift
    var removedBuiltInIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(removedBuiltInIDs), forKey: Keys.removedBuiltInIDs)
        }
    }

    var benchmarkSectionExpanded: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(benchmarkSectionExpanded), forKey: Keys.benchmarkSectionExpanded)
        }
    }
```

Update the `init`: after `self.providerOrder = defaults.stringArray(forKey: Keys.providerOrder) ?? []` (around line 71), add:

```swift
        self.removedBuiltInIDs = Set(defaults.stringArray(forKey: Keys.removedBuiltInIDs) ?? [])
        self.benchmarkSectionExpanded = Set(defaults.stringArray(forKey: Keys.benchmarkSectionExpanded) ?? [])
```

Update the `Keys` enum at the bottom of the file:

```swift
    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let launchAtLogin = "launchAtLogin"
        static let disabledProviderIDs = "disabledProviderIDs"
        static let iconStyle = "iconStyle"
        static let customProviderNames = "customProviderNames"
        static let providerOrder = "providerOrder"
        static let removedBuiltInIDs = "removedBuiltInIDs"
        static let benchmarkSectionExpanded = "benchmarkSectionExpanded"
    }
```

- [ ] **Step 2: Update ProviderConfigStore to honor removed built-ins and allow removal**

In `Sources/ProviderConfigStore.swift`, replace the `init` and `removeProvider` methods with:

```swift
    init(removedBuiltInIDs: Set<String> = []) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MenuStatus", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("providers.json")
        self.providers = ProviderConfig.builtInProviders.filter { !removedBuiltInIDs.contains($0.id) }
        loadFromDisk()
    }

    func removeProvider(id: String, settings: SettingsStore) {
        guard let provider = providers.first(where: { $0.id == id }) else { return }
        let enabledCount = providers.filter { settings.isEnabled($0) }.count
        let isEnabled = !settings.disabledProviderIDs.contains(id)
        // Prevent removing the last enabled provider
        guard !isEnabled || enabledCount > 1 else { return }

        providers.removeAll { $0.id == id }
        settings.disabledProviderIDs.remove(id)
        settings.providerOrder.removeAll { $0 == id }

        if provider.isBuiltIn {
            settings.removedBuiltInIDs.insert(id)
        } else {
            saveToDisk()
        }
    }

    func resetBuiltInProviders(settings: SettingsStore) {
        settings.removedBuiltInIDs.removeAll()
        for builtIn in ProviderConfig.builtInProviders {
            if !providers.contains(where: { $0.id == builtIn.id }) {
                providers.append(builtIn)
            }
        }
    }
```

Note: `SettingsStore.init` currently takes a `ProviderConfigStore` — there's an initialization order cycle to untangle. Create the settings first without providers, then create the provider store with the removed IDs, then attach it. Update the two callers in `MenuStatusApp.swift` in Task 6.

- [ ] **Step 3: Build to verify compile**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: BUILD FAILS — `SettingsStore.init` still requires `ProviderConfigStore`, and the MenuStatusApp.swift wiring hasn't changed yet. That's expected; proceed.

- [ ] **Step 4: Break the init cycle in SettingsStore**

In `Sources/SettingsStore.swift`, change the `providerConfigs` field from `let` to a late-bind:

```swift
    private(set) var providerConfigs: ProviderConfigStore!

    init() {
        let defaults = UserDefaults.standard

        if let interval = defaults.object(forKey: Keys.refreshInterval) as? TimeInterval, interval > 0 {
            self.refreshInterval = interval
        } else {
            self.refreshInterval = 60
        }
        self.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        if let ids = defaults.stringArray(forKey: Keys.disabledProviderIDs) {
            self.disabledProviderIDs = Set(ids)
        } else {
            self.disabledProviderIDs = []
        }
        self.iconStyle = MenuBarIconStyle(rawValue: defaults.integer(forKey: Keys.iconStyle)) ?? .outline
        self.customProviderNames = (defaults.dictionary(forKey: Keys.customProviderNames) as? [String: String]) ?? [:]
        self.providerOrder = defaults.stringArray(forKey: Keys.providerOrder) ?? []
        self.removedBuiltInIDs = Set(defaults.stringArray(forKey: Keys.removedBuiltInIDs) ?? [])
        self.benchmarkSectionExpanded = Set(defaults.stringArray(forKey: Keys.benchmarkSectionExpanded) ?? [])
    }

    func attachProviderConfigs(_ store: ProviderConfigStore) {
        self.providerConfigs = store
    }
```

Remove the old `init(providerConfigs:)` entirely and the stored `let providerConfigs` property.

- [ ] **Step 5: Commit (even if build still fails — wiring fixes in Task 6)**

```bash
git add Sources/SettingsStore.swift Sources/ProviderConfigStore.swift
git commit -m "feat: allow removing built-in providers with reset support"
```

---

## Task 6: Wire AIStupidLevelStore into App + Skip Fetching Benchmark-Only Providers

**Files:**
- Modify: `Sources/MenuStatusApp.swift`
- Modify: `Sources/StatusStore.swift:127-180`

- [ ] **Step 1: Update MenuStatusApp to construct and own AIStupidLevelStore**

Read the current `MenuStatusApp.swift` first to locate the `@State` declarations and MenuBarExtra body.

Find the existing `SettingsStore(providerConfigs: ProviderConfigStore())` instantiation. Replace that block with:

```swift
    @State private var settings: SettingsStore
    @State private var providerConfigs: ProviderConfigStore
    @State private var store: StatusStore
    @State private var benchmarkStore: AIStupidLevelStore
    @State private var updaterService = UpdaterService()

    init() {
        let settings = SettingsStore()
        let providerConfigs = ProviderConfigStore(removedBuiltInIDs: settings.removedBuiltInIDs)
        settings.attachProviderConfigs(providerConfigs)

        _settings = State(initialValue: settings)
        _providerConfigs = State(initialValue: providerConfigs)
        _store = State(initialValue: StatusStore(settings: settings))
        _benchmarkStore = State(initialValue: AIStupidLevelStore())
    }
```

Locate the view hierarchy that calls `store.startPolling()` (likely in `.task` on the MenuBarExtra content). Add `benchmarkStore.startPolling(interval: settings.refreshInterval)` alongside it. Add `benchmarkStore.stopPolling()` wherever `store.stopPolling()` is called.

Pass `benchmarkStore` down to `StatusMenuContentView`:

```swift
StatusMenuContentView(store: store, benchmarkStore: benchmarkStore)
```

(Task 8 adds the parameter to the view.)

- [ ] **Step 2: Make StatusStore skip benchmark-only providers**

In `Sources/StatusStore.swift`, in `refreshNow()` around line 132, change:

```swift
        let activeProviders = settings.providerConfigs.enabledProviders(settings: settings)
```

to:

```swift
        let activeProviders = settings.providerConfigs
            .enabledProviders(settings: settings)
            .filter { $0.hasStatusPage }
```

This ensures `fetchAllProviderData` never fires HTTP requests for `.aiStupidLevelOnly` providers. Their tabs render purely from `AIStupidLevelStore`.

Also update the similar reference if `summaries`/`componentTimelines` filters reference all enabled providers — they already key by provider, so absent keys just mean "no status data," which the view handles.

- [ ] **Step 3: Build**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: BUILD SUCCEEDED (views still reference old StatusMenuContentView signature — if the view compiles without the new param, leave it; we'll add it in Task 8. If it doesn't compile, temporarily pass `benchmarkStore` via an `@Environment` instead, or defer the `MenuStatusApp.swift` view-construction line change to Task 8.)

- [ ] **Step 4: Commit**

```bash
git add Sources/MenuStatusApp.swift Sources/StatusStore.swift
git commit -m "feat: wire AIStupidLevelStore into app; skip benchmark-only providers in StatusStore"
```

---

## Task 7: Benchmark Views

**Files:**
- Create: `Sources/BenchmarkViews.swift`

- [ ] **Step 1: Create the benchmark view file**

```swift
// Sources/BenchmarkViews.swift
import SwiftUI

// MARK: - Global Index Bar (top of menu popover)

struct GlobalIndexBar: View {
    let index: GlobalIndex

    private var trendColor: Color {
        switch index.trend {
        case "improving": return .green
        case "declining": return .red
        default: return .secondary
        }
    }

    private var trendSymbol: String {
        switch index.trend {
        case "improving": return "arrow.up"
        case "declining": return "arrow.down"
        default: return "arrow.right"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("AI Index")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Text("\(Int(index.current.globalScore.rounded()))")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Image(systemName: trendSymbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(trendColor)

            GlobalIndexSparkline(points: index.history.reversed())
                .frame(height: 16)
                .frame(maxWidth: .infinity)

            Text(index.trend.capitalized)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

private struct GlobalIndexSparkline: View {
    let points: [GlobalIndexPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let scores = points.map(\.globalScore)
            let minV = scores.min() ?? 0
            let maxV = scores.max() ?? 100
            let range = max(1, maxV - minV)

            var path = Path()
            for (i, score) in scores.enumerated() {
                let x = CGFloat(i) / CGFloat(scores.count - 1) * size.width
                let y = size.height - CGFloat((score - minV) / range) * size.height
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.stroke(
                path,
                with: .color(.primary.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Benchmark Section (inside a provider tab)

struct BenchmarkSection: View {
    let summary: BenchmarkVendorSummary
    let isExpanded: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — click to toggle
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .scaleEffect(isHovered ? 1.2 : 1.0)

                    Text("Model Benchmarks")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(summaryLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .animation(.easeInOut(duration: 0.15), value: isHovered)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(summary.scores) { score in
                        BenchmarkModelRow(score: score)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private var summaryLine: String {
        let count = summary.scores.count
        let avg = Int(summary.averageScore.rounded())
        var parts = ["\(count) model\(count == 1 ? "" : "s")", "avg \(avg)"]
        if summary.warningCount > 0 { parts.append("\(summary.warningCount) warn") }
        if summary.criticalCount > 0 { parts.append("\(summary.criticalCount) crit") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Single Model Row

struct BenchmarkModelRow: View {
    let score: BenchmarkScore

    var body: some View {
        HStack(spacing: 8) {
            Text(score.name)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)

            ScoreBar(score: score.currentScore, lower: score.confidenceLower, upper: score.confidenceUpper, color: score.status.color)
                .frame(height: 8)
                .frame(maxWidth: .infinity)

            Text("\(Int(score.currentScore.rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(width: 22, alignment: .trailing)

            Image(systemName: score.trend.symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(score.trend.color)
                .frame(width: 10)
        }
    }
}

private struct ScoreBar: View {
    let score: Double
    let lower: Double?
    let upper: Double?
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let clampedScore = min(100, max(0, score))
            let scoreWidth = w * clampedScore / 100

            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.08))

                // Confidence interval
                if let lower, let upper {
                    let lowerClamped = min(100, max(0, lower))
                    let upperClamped = min(100, max(0, upper))
                    let ciStart = w * lowerClamped / 100
                    let ciEnd = w * upperClamped / 100
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.25))
                        .frame(width: max(0, ciEnd - ciStart))
                        .offset(x: ciStart)
                }

                // Score bar
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color)
                    .frame(width: scoreWidth)
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/BenchmarkViews.swift
git commit -m "feat: add benchmark views (global index bar, section, model row)"
```

---

## Task 8: Integrate GlobalIndexBar into Menu Content

**Files:**
- Modify: `Sources/StatusMenuContentView.swift:9-80`

- [ ] **Step 1: Add benchmarkStore parameter and render GlobalIndexBar**

In `Sources/StatusMenuContentView.swift`, update the struct declaration:

```swift
struct StatusMenuContentView: View {
    let store: StatusStore
    let benchmarkStore: AIStupidLevelStore
    @Environment(\.openWindow) private var openWindow
    @State private var selectedProvider: ProviderConfig?
    // ... rest unchanged
```

In the `body` `VStack`, insert the Global Index bar between the tab grid and the content area (after the tab bar's `Divider`, before the `if needsScroll` block):

```swift
            // Tab bar
            VStack(spacing: 0) {
                ProviderTabGrid(...)
                    .padding(...)
                Divider()
            }
            .background { ... headerHeight GeometryReader ... }

            // Global Index bar (only when benchmark data loaded)
            if let globalIndex = benchmarkStore.globalIndex {
                GlobalIndexBar(index: globalIndex)
                Divider()
            }

            // Selected provider content
            if needsScroll { ... }
```

Note: `headerHeight` measurement background currently wraps only the tab-bar VStack. Move that background to wrap both the tab-bar VStack **and** the new Global Index bar (wrap them in an outer `VStack(spacing: 0) { ... }` and put the GeometryReader background on the outer VStack). This keeps `maxVisibleContentHeight` math correct.

- [ ] **Step 2: Update MenuStatusApp to pass benchmarkStore to the view**

If not already done in Task 6, in `Sources/MenuStatusApp.swift` update the `StatusMenuContentView(store: store)` call site to `StatusMenuContentView(store: store, benchmarkStore: benchmarkStore)`.

- [ ] **Step 3: Build and run**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: BUILD SUCCEEDED

Then: `./run-menubar.sh`
Expected (manual): Menu popover opens. OpenAI and Anthropic tabs still render their status components normally. After ~1s benchmark fetch completes, a thin "AI Index 84 ↓ ····· Declining" bar appears under the tab grid.

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusMenuContentView.swift Sources/MenuStatusApp.swift
git commit -m "feat: render global AI index bar in menu popover"
```

---

## Task 9: Integrate BenchmarkSection into ProviderSectionView

**Files:**
- Modify: `Sources/StatusRowViews.swift:10-85`
- Modify: `Sources/StatusMenuContentView.swift` (pass benchmarkStore into ProviderSectionView)

- [ ] **Step 1: Pass benchmarkStore through ProviderSectionView**

In `Sources/StatusRowViews.swift`, update the struct signature:

```swift
struct ProviderSectionView: View {
    let provider: ProviderConfig
    let summary: StatuspageSummary?  // Now optional — benchmark-only providers pass nil
    let store: StatusStore
    let benchmarkStore: AIStupidLevelStore
    let settings: SettingsStore

    private var visibleComponents: [Component] {
        (summary?.components ?? []).filter { $0.group != true }
    }

    private var activeIncidents: [Incident] {
        (summary?.incidents ?? []).filter { $0.status.isActive }
    }

    private var groupedSections: [GroupedComponentSection] {
        store.sections(for: provider)
    }

    private var benchmarkSummary: BenchmarkVendorSummary? {
        guard let vendor = provider.aiStupidLevelVendor else { return nil }
        let summary = benchmarkStore.summary(forVendor: vendor)
        return summary.isEmpty ? nil : summary
    }

    private var benchmarkExpanded: Bool {
        settings.benchmarkSectionExpanded.contains(provider.id)
    }

    private func toggleBenchmarkExpanded() {
        if settings.benchmarkSectionExpanded.contains(provider.id) {
            settings.benchmarkSectionExpanded.remove(provider.id)
        } else {
            settings.benchmarkSectionExpanded.insert(provider.id)
        }
    }
```

- [ ] **Step 2: Restructure `body` to support benchmark-only + hybrid rendering**

Replace the existing `body`:

```swift
    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if let summary {
                statusPageContent(summary: summary)
            } else {
                benchmarkOnlyHeader
            }

            if let benchmarkSummary {
                if summary != nil {
                    Divider().padding(.horizontal, 16).padding(.vertical, 4)
                }
                BenchmarkSection(
                    summary: benchmarkSummary,
                    isExpanded: benchmarkExpanded,
                    onToggle: toggleBenchmarkExpanded
                )
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusPageContent(summary: StatuspageSummary) -> some View {
        HStack {
            Label(summary.status.indicator.displayName, systemImage: summary.status.indicator.sfSymbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(summary.status.indicator.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)

        if !activeIncidents.isEmpty {
            ForEach(activeIncidents) { incident in
                IncidentRow(incident: incident)
            }
            .padding(.bottom, 4)
        }

        Divider().padding(.horizontal, 16)

        if groupedSections.isEmpty {
            ForEach(visibleComponents) { component in
                ComponentUptimeRow(
                    component: component,
                    timeline: store.timeline(for: provider, componentId: component.id),
                    dayDetails: store.dayDetails(for: provider, componentId: component.id),
                    statusPageURL: provider.statusPageURL
                )
            }
        } else {
            ForEach(groupedSections) { section in
                GroupHeaderView(
                    section: section,
                    isExpanded: store.isExpanded(section, provider: provider),
                    provider: provider,
                    store: store,
                    dayDetails: store.dayDetails(for: provider, section: section)
                )
                if store.isExpanded(section, provider: provider) {
                    ForEach(section.components) { component in
                        ComponentUptimeRow(
                            component: component,
                            timeline: store.timeline(for: provider, componentId: component.id),
                            dayDetails: store.dayDetails(for: provider, componentId: component.id),
                            statusPageURL: provider.statusPageURL,
                            contentPaddingLeading: 30
                        )
                    }
                }
            }
        }
    }

    private var benchmarkOnlyHeader: some View {
        HStack {
            Label("Benchmarks only", systemImage: "chart.bar.xaxis")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
```

- [ ] **Step 3: Update call site in StatusMenuContentView**

In `Sources/StatusMenuContentView.swift`, replace `selectedProviderContent`:

```swift
    @ViewBuilder
    private var selectedProviderContent: some View {
        if let provider = activeProvider {
            if provider.hasStatusPage, let summary = store.summaries[provider] {
                ProviderSectionView(
                    provider: provider,
                    summary: summary,
                    store: store,
                    benchmarkStore: benchmarkStore,
                    settings: store.settings
                )
            } else if !provider.hasStatusPage {
                ProviderSectionView(
                    provider: provider,
                    summary: nil,
                    store: store,
                    benchmarkStore: benchmarkStore,
                    settings: store.settings
                )
            } else {
                loadingPlaceholder
            }
        } else {
            loadingPlaceholder
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
```

- [ ] **Step 4: Ensure ProviderTab dots don't crash for benchmark-only providers**

In `Sources/StatusMenuContentView.swift`, locate `ProviderTabGrid` where it passes `indicator: summaries[provider]?.status.indicator`. This already returns `nil` for benchmark-only providers — no change needed, the dot just won't show.

- [ ] **Step 5: Build and run**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build && ./run-menubar.sh`
Expected (manual):
- OpenAI/Anthropic tabs render status components as before, with a collapsible "Model Benchmarks" section at the bottom. Header shows "5 models · avg 58 · 2 warn". Click expands.
- xAI/Kimi/Google/GLM/DeepSeek tabs render "Benchmarks only" header + the collapsible benchmark section.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusRowViews.swift Sources/StatusMenuContentView.swift
git commit -m "feat: render per-vendor benchmark section in provider tabs"
```

---

## Task 10: Settings — Reset Built-in Providers Button

**Files:**
- Modify: `Sources/SettingsView.swift`

- [ ] **Step 1: Add a Reset button to the providers section**

Open `Sources/SettingsView.swift` and locate the Section containing the providers List. Below the List (and any existing Add/Import buttons), add:

```swift
                Button("Reset built-in providers") {
                    settings.providerConfigs.resetBuiltInProviders(settings: settings)
                }
                .help("Restore any built-in providers you have deleted")
                .disabled(settings.removedBuiltInIDs.isEmpty)
```

- [ ] **Step 2: Build and run**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build && ./run-menubar.sh`
Expected (manual): Open Settings. Delete a built-in vendor (e.g., GLM) — it disappears from the tab bar. Click "Reset built-in providers" — GLM returns.

- [ ] **Step 3: Run all tests**

Run: `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/SettingsView.swift
git commit -m "feat: add reset button for built-in providers in settings"
```

---

## Post-Implementation Manual QA Checklist

Launch `./run-menubar.sh` and verify:

- [ ] Menu opens without flicker (initial measurement opacity guard still works)
- [ ] GlobalIndexBar appears after benchmark fetch completes (~1s delay on first open)
- [ ] OpenAI tab shows status components + collapsible Model Benchmarks section below (default collapsed)
- [ ] Expanding the benchmark section shows model rows with score bars, trend arrows, confidence intervals
- [ ] xAI / Google / Kimi / GLM / DeepSeek tabs are present and show only the benchmark section
- [ ] Menu bar icon color is unchanged (benchmark status does not affect it)
- [ ] Settings → delete a benchmark-only provider removes it from the tab bar
- [ ] Settings → "Reset built-in providers" restores it
- [ ] Network offline: existing "Offline" label still works; benchmark store shows stale data gracefully
- [ ] Stop the app (`./stop-menubar.sh`) and relaunch: removed built-ins stay removed; expanded benchmark sections stay expanded

---

## Self-Review Notes

- `ProviderConfig` Codable is backwards-compatible: old on-disk JSON without `aiStupidLevelVendor` decodes `nil` (optional).
- `StatusPlatform` adds a new case — old JSON on disk only contains `.atlassianStatuspage` / `.incidentIO`, so decode succeeds.
- `StatusStore.refreshNow` filters `hasStatusPage` so no HTTP fetches fire for `.aiStupidLevelOnly` providers.
- `AIStupidLevelStore` is fully independent; it does not affect `overallIndicator`, so the menu bar icon is unchanged by benchmark fluctuations, per the design decision.
- The benchmark section's expansion state is persisted in `UserDefaults` via `benchmarkSectionExpanded: Set<String>`, keyed by provider ID (distinct from `StatusStore.groupExpansionOverrides` which is in-memory only).
- Benchmark-only providers hold a `benchmarkPlaceholder` `baseURL` that is never fetched; this avoids making `baseURL` optional throughout the codebase (which would cascade into many call sites).
- Per-model history (`/api/models/:id/history`) and degradation annotations are intentionally out of scope for v1; wire them in a follow-up if the section feels too bare.

## Execution Handoff

Plan complete. Two execution options:

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** — execute tasks in this session using executing-plans, batch checkpoints

Which approach?
