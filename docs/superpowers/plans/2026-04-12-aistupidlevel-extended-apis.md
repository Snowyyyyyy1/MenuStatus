# AI Stupid Level extended public APIs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend MenuStatus’s AI Stupid Level integration to fetch and display **dashboard alerts**, **batch status**, **analytics recommendations**, **provider reliability**, **degradations**, and **on-demand per-model history**, with **header insights** plus **per-vendor tab enrichment**, matching `docs/superpowers/specs/2026-04-12-aistupidlevel-extended-apis-design.md`.

**Architecture:** Add `Decodable` types and static decode helpers on `AIStupidLevelClient` (same pattern as `decodeScores` / `decodeGlobalIndex`). `AIStupidLevelStore.refreshNow()` runs **structured concurrent fetches** for core + extension endpoints; each extension updates state in isolation so failures **never clear** `scores` / `globalIndex`. New SwiftUI views live in **`Sources/BenchmarkInsightsViews.swift`**; `StatusMenuContentView` only wires them under the existing header `VStack`. Vendor-scoped rows reuse **filtered copies** of store arrays (helper methods on the store). History loads **only** from explicit UI action via `loadHistoryIfNeeded(modelId:)`.

**Tech stack:** Swift 5.9+, SwiftUI, Observation (`@Observable`), `URLSession`, XCTest (`@testable import MenuStatus`), Tuist (`Sources/**`, `Tests/**`).

**Spec:** `docs/superpowers/specs/2026-04-12-aistupidlevel-extended-apis-design.md`

---

## File map (before tasks)

| File | Role |
|------|------|
| `Sources/AIStupidLevelAnalyticsModels.swift` | **Create** — Decodable payloads for alerts, batch-status, recommendations, degradations, reliability, model history |
| `Sources/AIStupidLevelClient.swift` | **Modify** — `fetchData(path:)`, new `fetch*` + `decode*` static methods |
| `Sources/AIStupidLevelStore.swift` | **Modify** — New properties, `refreshNow` concurrency, vendor filters, history cache + `loadHistoryIfNeeded` |
| `Sources/BenchmarkInsightsViews.swift` | **Create** — `BenchmarkInsightsHeaderBar` (alerts / batch / recommendation summary + link-out) |
| `Sources/BenchmarkViews.swift` | **Modify** — Extend `BenchmarkSection` / `BenchmarkModelRow` for tab extras + optional history disclosure |
| `Sources/StatusMenuContentView.swift` | **Modify** — Insert insights view below `GlobalIndexBar` inside header `VStack` |
| `Sources/StatusRowViews.swift` | **Modify** — Pass `benchmarkStore` + `provider` into `BenchmarkSection` (or pass pre-filtered structs) |
| `Tests/AIStupidLevelClientTests.swift` | **Modify** — Fixture decode tests for each new payload |
| `Tests/AIStupidLevelStoreTests.swift` | **Modify** — Vendor filtering + history cache behavior |

---

### Task 1: Analytics models file

**Files:**

- Create: `Sources/AIStupidLevelAnalyticsModels.swift`

- [ ] **Step 1: Add file with Decodable types (copy verbatim)**

```swift
import Foundation

// MARK: - Alerts — GET /api/dashboard/alerts

struct DashboardAlertsResponse: Decodable {
    let success: Bool
    let data: [DashboardAlert]
}

struct DashboardAlert: Decodable, Identifiable, Hashable {
    var id: String { "\(name)-\(detectedAt ?? "")" }
    let name: String
    let provider: String
    let issue: String?
    let severity: String?
    let detectedAt: String?
}

// MARK: - Batch status — GET /api/dashboard/batch-status

struct DashboardBatchStatusResponse: Decodable {
    let success: Bool
    let data: DashboardBatchStatusData
}

struct DashboardBatchStatusData: Decodable {
    let isBatchInProgress: Bool?
    let schedulerRunning: Bool?
    let nextScheduledRun: String?
}

// MARK: - Recommendations — GET /api/analytics/recommendations

struct AnalyticsRecommendationsResponse: Decodable {
    let success: Bool
    let data: AnalyticsRecommendationsPayload
}

struct AnalyticsRecommendationsPayload: Decodable {
    let bestForCode: AnalyticsRecommendationSlot?
    let mostReliable: AnalyticsRecommendationSlot?
    let fastestResponse: AnalyticsRecommendationSlot?
    let avoidNow: [AnalyticsRecommendationSlot]?
}

struct AnalyticsRecommendationSlot: Decodable, Hashable {
    let id: String?
    let name: String?
    let vendor: String?
    let score: Double?
    let lastUpdate: String?
    let displayScore: Double?
    let rank: Int?
    let reason: String?
    let evidence: String?
    let correctness: Double?
    let codeQuality: Double?
    let stabilityScore: Double?
}

// MARK: - Degradations — GET /api/analytics/degradations

struct AnalyticsDegradationsResponse: Decodable {
    let success: Bool
    let data: [AnalyticsDegradationItem]
}

struct AnalyticsDegradationItem: Decodable, Identifiable, Hashable {
    var id: String { "\(modelId)-\(detectedAt ?? "")" }
    let modelId: Int
    let modelName: String?
    let provider: String?
    let currentScore: Double?
    let baselineScore: Double?
    let dropPercentage: Double?
    let severity: String?
    let detectedAt: String?
    let message: String?
    let type: String?
}

// MARK: - Provider reliability — GET /api/analytics/provider-reliability

struct ProviderReliabilityResponse: Decodable {
    let success: Bool
    let data: [ProviderReliabilityRow]
    let timestamp: String?
}

struct ProviderReliabilityRow: Decodable, Identifiable, Hashable {
    var id: String { provider }
    let provider: String
    let trustScore: Int?
    let totalIncidents: Int?
    let incidentsPerMonth: Int?
    let avgRecoveryHours: String?
    let lastIncident: String?
    let trend: String?
    let isAvailable: Bool?
}

// MARK: - Model history — GET /api/models/:id/history (no {success,data} wrapper)

struct ModelHistoryPayload: Decodable {
    let modelId: Int
    let period: String?
    let sortBy: String?
    let dataPoints: Int?
    let timeRange: String?
    let history: [ModelHistoryPoint]
}

struct ModelHistoryPoint: Decodable, Hashable {
    let timestamp: String
    let stupidScore: Double?
    let displayScore: Double?
}
```

- [ ] **Step 2: Build**

Run:

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
git add Sources/AIStupidLevelAnalyticsModels.swift
git commit -m "feat: add AI Stupid Level analytics Decodable models"
```

---

### Task 2: Client decode helpers + XCTest fixtures

**Files:**

- Modify: `Sources/AIStupidLevelClient.swift`
- Modify: `Tests/AIStupidLevelClientTests.swift`

- [ ] **Step 1: Append static decode helpers to `AIStupidLevelClient` (inside struct, before `fetchData`)**

```swift
    static func decodeDashboardAlerts(_ data: Data) throws -> [DashboardAlert] {
        let response = try decoder.decode(DashboardAlertsResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("alerts success=false") }
        return response.data
    }

    static func decodeBatchStatus(_ data: Data) throws -> DashboardBatchStatusData {
        let response = try decoder.decode(DashboardBatchStatusResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("batch-status success=false") }
        return response.data
    }

    static func decodeRecommendations(_ data: Data) throws -> AnalyticsRecommendationsPayload {
        let response = try decoder.decode(AnalyticsRecommendationsResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("recommendations success=false") }
        return response.data
    }

    static func decodeDegradations(_ data: Data) throws -> [AnalyticsDegradationItem] {
        let response = try decoder.decode(AnalyticsDegradationsResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("degradations success=false") }
        return response.data
    }

    static func decodeProviderReliability(_ data: Data) throws -> [ProviderReliabilityRow] {
        let response = try decoder.decode(ProviderReliabilityResponse.self, from: data)
        guard response.success else { throw AIStupidLevelClientError.apiFailure("provider-reliability success=false") }
        return response.data
    }

    static func decodeModelHistory(_ data: Data) throws -> ModelHistoryPayload {
        try decoder.decode(ModelHistoryPayload.self, from: data)
    }
```

- [ ] **Step 2: Add tests — append to `AIStupidLevelClientTests`**

```swift
    func testDecodeDashboardAlerts() throws {
        let json = """
        {"success":true,"data":[
          {"name":"m1","provider":"openai","issue":"tasks failed","severity":"warning","detectedAt":"2026-04-11T15:00:00.039Z"}
        ]}
        """
        let rows = try AIStupidLevelClient.decodeDashboardAlerts(Data(json.utf8))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].provider, "openai")
        XCTAssertEqual(rows[0].severity, "warning")
    }

    func testDecodeBatchStatus() throws {
        let json = """
        {"success":true,"data":{"isBatchInProgress":false,"schedulerRunning":true,"nextScheduledRun":"2026-04-11T18:00:00.000Z"}}
        """
        let b = try AIStupidLevelClient.decodeBatchStatus(Data(json.utf8))
        XCTAssertEqual(b.nextScheduledRun, "2026-04-11T18:00:00.000Z")
        XCTAssertEqual(b.schedulerRunning, true)
    }

    func testDecodeRecommendations() throws {
        let json = """
        {"success":true,"data":{
          "bestForCode":{"id":"204","name":"gpt-5.2","vendor":"openai","score":68,"rank":1,"reason":"Ranked #1"},
          "mostReliable":null,
          "fastestResponse":null,
          "avoidNow":[]
        }}
        """
        let p = try AIStupidLevelClient.decodeRecommendations(Data(json.utf8))
        XCTAssertEqual(p.bestForCode?.name, "gpt-5.2")
        XCTAssertEqual(p.bestForCode?.vendor, "openai")
    }

    func testDecodeDegradations() throws {
        let json = """
        {"success":true,"data":[
          {"modelId":165,"modelName":"glm-4.6","provider":"glm","currentScore":40,"baselineScore":65,"severity":"critical","detectedAt":"2026-04-11T16:00:00.000Z","message":"Critical","type":"critical_failure"}
        ]}
        """
        let d = try AIStupidLevelClient.decodeDegradations(Data(json.utf8))
        XCTAssertEqual(d[0].modelId, 165)
        XCTAssertEqual(d[0].provider, "glm")
    }

    func testDecodeProviderReliability() throws {
        let json = """
        {"success":true,"data":[
          {"provider":"openai","trustScore":81,"totalIncidents":1,"avgRecoveryHours":"1.2","trend":"reliable","isAvailable":true}
        ],"timestamp":"2026-04-11T16:00:00.000Z"}
        """
        let r = try AIStupidLevelClient.decodeProviderReliability(Data(json.utf8))
        XCTAssertEqual(r[0].trustScore, 81)
        XCTAssertEqual(r[0].avgRecoveryHours, "1.2")
    }

    func testDecodeModelHistory() throws {
        let json = """
        {"modelId":38,"period":"30 days","sortBy":"combined","dataPoints":2,"timeRange":"30d","history":[
          {"timestamp":"2026-04-11T15:00:00.039Z","stupidScore":74,"displayScore":74}
        ]}
        """
        let h = try AIStupidLevelClient.decodeModelHistory(Data(json.utf8))
        XCTAssertEqual(h.modelId, 38)
        XCTAssertEqual(h.history.count, 1)
        XCTAssertEqual(h.history[0].stupidScore, 74)
    }
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build -only-testing:MenuStatusTests/AIStupidLevelClientTests
```

Expected: **Test Suite 'AIStupidLevelClientTests' passed**

- [ ] **Step 4: Commit**

```bash
git add Sources/AIStupidLevelClient.swift Tests/AIStupidLevelClientTests.swift
git commit -m "feat: decode AI Stupid Level analytics JSON in client"
```

---

### Task 3: Client `fetch*` methods

**Files:**

- Modify: `Sources/AIStupidLevelClient.swift`

- [ ] **Step 1: Add fetch methods (same session / error style as existing)**

```swift
    static func fetchDashboardAlerts() async throws -> [DashboardAlert] {
        let data = try await fetchData(path: "/api/dashboard/alerts")
        return try decodeDashboardAlerts(data)
    }

    static func fetchBatchStatus() async throws -> DashboardBatchStatusData {
        let data = try await fetchData(path: "/api/dashboard/batch-status")
        return try decodeBatchStatus(data)
    }

    static func fetchRecommendations() async throws -> AnalyticsRecommendationsPayload {
        let data = try await fetchData(path: "/api/analytics/recommendations")
        return try decodeRecommendations(data)
    }

    static func fetchDegradations() async throws -> [AnalyticsDegradationItem] {
        let data = try await fetchData(path: "/api/analytics/degradations")
        return try decodeDegradations(data)
    }

    static func fetchProviderReliability() async throws -> [ProviderReliabilityRow] {
        let data = try await fetchData(path: "/api/analytics/provider-reliability")
        return try decodeProviderReliability(data)
    }

    static func fetchModelHistory(modelId: String) async throws -> ModelHistoryPayload {
        let path = "/api/models/\(modelId)/history"
        let data = try await fetchData(path: path)
        return try decodeModelHistory(data)
    }
```

- [ ] **Step 2: Build**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 3: Commit**

```bash
git add Sources/AIStupidLevelClient.swift
git commit -m "feat: fetch AI Stupid Level analytics endpoints"
```

---

### Task 4: Store — parallel refresh + properties

**Files:**

- Modify: `Sources/AIStupidLevelStore.swift`

- [ ] **Step 1: Add properties (top of class, after existing vars)**

```swift
    var dashboardAlerts: [DashboardAlert] = []
    var batchStatus: DashboardBatchStatusData?
    var recommendations: AnalyticsRecommendationsPayload?
    var degradations: [AnalyticsDegradationItem] = []
    var providerReliability: [ProviderReliabilityRow] = []
    var historyByModelID: [String: ModelHistoryPayload] = [:]
```

- [ ] **Step 2: Replace `refreshNow()` body fetch section** so that after `isLoading = true`, you run **one `async let` per request**, then **`do`/`catch` (or `try?`) per assignment** — do not use `Result { }` with `async let` (invalid). Example:

```swift
        async let scoresTask = AIStupidLevelClient.fetchScores()
        async let globalTask = AIStupidLevelClient.fetchGlobalIndex()
        async let alertsTask = AIStupidLevelClient.fetchDashboardAlerts()
        async let batchTask = AIStupidLevelClient.fetchBatchStatus()
        async let recoTask = AIStupidLevelClient.fetchRecommendations()
        async let degTask = AIStupidLevelClient.fetchDegradations()
        async let relTask = AIStupidLevelClient.fetchProviderReliability()

        do { self.scores = try await scoresTask }
        catch { self.errorMessage = "Benchmark scores: \(error.localizedDescription)" }

        do { self.globalIndex = try await globalTask }
        catch {
            if self.errorMessage == nil { self.errorMessage = "Global index: \(error.localizedDescription)" }
        }

        do { self.dashboardAlerts = try await alertsTask }
        catch { }

        do { self.batchStatus = try await batchTask }
        catch { self.batchStatus = nil }

        do { self.recommendations = try await recoTask }
        catch { self.recommendations = nil }

        do { self.degradations = try await degTask }
        catch { self.degradations = [] }

        do { self.providerReliability = try await relTask }
        catch { self.providerReliability = [] }
```

Keep existing `lastRefreshed` / `isLoading = false` at end. **Do not** set `errorMessage` for extension-only failures (spec: silent omission).

- [ ] **Step 3: Add history loader (`AIStupidLevelStore` is `@MainActor`)**

```swift
    private var historyFetchTasks: [String: Task<Void, Never>] = [:]

    func loadHistoryIfNeeded(modelId: String) {
        if historyByModelID[modelId] != nil { return }
        if historyFetchTasks[modelId] != nil { return }
        historyFetchTasks[modelId] = Task { [weak self] in
            guard let self else { return }
            defer { self.historyFetchTasks[modelId] = nil }
            do {
                let payload = try await AIStupidLevelClient.fetchModelHistory(modelId: modelId)
                self.historyByModelID[modelId] = payload
            } catch {
                // silent — no errorMessage for extension (per spec)
            }
        }
    }
```

If the compiler warns about `Task` capturing `self`, use `Task { @MainActor [weak self] in ... }` explicitly.

- [ ] **Step 4: Build**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 5: Commit**

```bash
git add Sources/AIStupidLevelStore.swift
git commit -m "feat: refresh AI Stupid Level analytics in store"
```

---

### Task 5: Store vendor filters + tests

**Files:**

- Modify: `Sources/AIStupidLevelStore.swift`
- Modify: `Tests/AIStupidLevelStoreTests.swift`

- [ ] **Step 1: Add helpers on `AIStupidLevelStore`**

```swift
    func alerts(forVendor vendor: String) -> [DashboardAlert] {
        let v = vendor.lowercased()
        return dashboardAlerts.filter { $0.provider.lowercased() == v }
    }

    func degradations(forVendor vendor: String) -> [AnalyticsDegradationItem] {
        let v = vendor.lowercased()
        return degradations.filter { ($0.provider ?? "").lowercased() == v }
    }

    func reliability(forVendor vendor: String) -> ProviderReliabilityRow? {
        let v = vendor.lowercased()
        return providerReliability.first { $0.provider.lowercased() == v }
    }

    func recommendationLine(forVendor vendor: String) -> String? {
        let v = vendor.lowercased()
        let slots: [AnalyticsRecommendationSlot?] = [
            recommendations?.bestForCode,
            recommendations?.mostReliable,
            recommendations?.fastestResponse,
        ]
        for slot in slots {
            guard let s = slot, let sv = s.vendor?.lowercased(), sv == v else { continue }
            if let name = s.name, let reason = s.reason { return "\(name): \(reason)" }
            if let name = s.name { return name }
        }
        return nil
    }
```

- [ ] **Step 2: Add tests in `AIStupidLevelStoreTests`**

Construct a store, set `dashboardAlerts` / `degradations` / `recommendations` / `providerReliability` directly, assert `alerts(forVendor:)`, `degradations(forVendor:)`, `recommendationLine(forVendor:)`, `reliability(forVendor:)` for `openai` vs `anthropic`.

- [ ] **Step 3: Run tests**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build -only-testing:MenuStatusTests/AIStupidLevelStoreTests
```

Expected: **passed**

- [ ] **Step 4: Commit**

```bash
git add Sources/AIStupidLevelStore.swift Tests/AIStupidLevelStoreTests.swift
git commit -m "test: vendor-scoped AI Stupid Level analytics helpers"
```

---

### Task 6: Header insights UI

**Files:**

- Create: `Sources/BenchmarkInsightsViews.swift`
- Modify: `Sources/StatusMenuContentView.swift`

- [ ] **Step 1: Implement `BenchmarkInsightsHeaderBar`**

Inputs: `benchmarkStore: AIStupidLevelStore`. Layout: compact `HStack` / `VStack` (max 2 lines), **12–13pt** secondary text consistent with `GlobalIndexBar`. Content:

- If `!dashboardAlerts.isEmpty`: `Image(systemName: "exclamationmark.triangle.fill")` + `Text("\(dashboardAlerts.count) alerts")` + optional highest severity (derive max from known severities `critical` > `warning` > others).
- If `let next = batchStatus?.nextScheduledRun`: show `Next run` with ISO string trimmed to time (or use `ISO8601DateFormatter` + `DateFormatter` short style if parse succeeds).
- If `let slot = recommendations?.bestForCode`, show `Best (code): \(slot.name ?? "?")`.
- Wrap in `Button` or separate `Link`-style `Button` that calls `NSWorkspace.shared.open(URL(string: "https://aistupidlevel.info/")!)`.

Use `.buttonStyle(.plain)` + small hover if needed (match `FooterIconHover` philosophy only if trivial; otherwise skip hover).

- [ ] **Step 2: Wire in `StatusMenuContentView`** — immediately after:

```swift
                if let globalIndex = benchmarkStore.globalIndex {
                    GlobalIndexBar(index: globalIndex)
                    Divider()
                }
```

insert:

```swift
                BenchmarkInsightsHeaderBar(benchmarkStore: benchmarkStore)
                Divider()
```

Only when **any** of `dashboardAlerts`, `batchStatus?.nextScheduledRun`, `recommendations?.bestForCode` is non-nil / non-empty — else **omit entire block** (including extra `Divider`) to avoid empty chrome. Implement that guard inside `BenchmarkInsightsHeaderBar` returning `EmptyView()` when nothing to show.

- [ ] **Step 3: Build + manual smoke**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build && ./run-menubar.sh
```

Confirm: popover opens, header height still reasonable, no layout collapse (see `CLAUDE.md` ScrollView guard — unchanged).

- [ ] **Step 4: Commit**

```bash
git add Sources/BenchmarkInsightsViews.swift Sources/StatusMenuContentView.swift
git commit -m "feat: benchmark insights bar under global index"
```

---

### Task 7: Tab `BenchmarkSection` enrichment + on-demand history

**Files:**

- Modify: `Sources/BenchmarkViews.swift`
- Modify: `Sources/StatusRowViews.swift`

- [ ] **Step 1: Extend `BenchmarkSection` signature**

Add parameters:

```swift
    let vendor: String
    let benchmarkStore: AIStupidLevelStore
```

Inside expanded `VStack`, **above** the `ForEach(summary.scores)`:

- If `!benchmarkStore.alerts(forVendor: vendor).isEmpty`: small `Text` list (cap at 3 lines + “…” ) or `DisclosureGroup` titled “Alerts”.
- If `!benchmarkStore.degradations(forVendor: vendor).isEmpty`: same for degradations (show `modelName`, `message` or `severity`).
- If `let line = benchmarkStore.recommendationLine(forVendor: vendor)`: one `Text(line).font(.caption).foregroundStyle(.secondary)`.
- If `let row = benchmarkStore.reliability(forVendor: vendor)`: one line `Trust \(row.trustScore ?? 0)`.

- [ ] **Step 2: Extend `BenchmarkModelRow`**

Add optional `onShowTrend: (() -> Void)?` and `history: ModelHistoryPayload?` — parent passes `benchmarkStore.historyByModelID[score.id]` and `onShowTrend: { benchmarkStore.loadHistoryIfNeeded(modelId: score.id) }`.

When user taps a small `Button("趋势")` or chevron: call `onShowTrend?()`; when `history` becomes non-nil, show a **thin** `Canvas` sparkline from `history.history` using `stupidScore ?? displayScore ?? 0` (skip points with nil scores).

- [ ] **Step 3: Update `ProviderSectionView`** `BenchmarkSection` call site**

```swift
                BenchmarkSection(
                    vendor: vendor,
                    benchmarkStore: benchmarkStore,
                    summary: benchmarkSummary,
                    isExpanded: benchmarkExpanded,
                    onToggle: toggleBenchmarkExpanded
                )
```

- [ ] **Step 4: Build + `./run-menubar.sh`**

Expected: expanding benchmarks shows vendor-specific blocks; tapping trend triggers network (watch Console if needed).

- [ ] **Step 5: Commit**

```bash
git add Sources/BenchmarkViews.swift Sources/StatusRowViews.swift
git commit -m "feat: vendor benchmark alerts, degradations, history sparkline"
```

---

### Task 8: Final verification + polish pass

- [ ] **Step 1: Full test target**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

Expected: **all tests pass**

- [ ] **Step 2: `read_lints` / Xcode warnings** — fix any new Swift 6 concurrency warnings (`Sendable`, etc.) in `Task` closures.

- [ ] **Step 3: Commit if fixes**

```bash
git add -A && git commit -m "fix: polish AI Stupid Level analytics integration" || true
```

---

## Plan self-review (vs spec)

| Spec requirement | Task coverage |
|------------------|---------------|
| Header insights (alerts, batch, recommendations, optional reliability) | Task 6 (+ reliability line in Task 7 tab if header omitted) |
| Extension failures silent, never clear scores/global | Task 4 (`case .failure: break` / nil / empty) |
| Tab vendor filtering + recommendation line | Task 5, 7 |
| On-demand history, no N+1 on refresh | Task 4 `loadHistoryIfNeeded`, Task 7 UI trigger |
| No `MenuBarExtra` label `.task` | Not touched (only popover views) |
| Header `GeometryReader` / scroll safeguards | Task 6 conditional rendering + no structural change to `needsScroll` |
| Tests for decode + store filters | Tasks 2, 5 |

**Placeholder scan:** none intentional.

**Type name consistency:** `DashboardAlert`, `ModelHistoryPayload`, `AnalyticsRecommendationSlot` used consistently across client/store/views.

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-12-aistupidlevel-extended-apis.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — Fresh subagent per task, review between tasks, fast iteration. **REQUIRED SUB-SKILL:** `superpowers:subagent-driven-development`.

2. **Inline Execution** — Execute tasks in this session with checkpoints. **REQUIRED SUB-SKILL:** `superpowers:executing-plans`.

Which approach do you want for implementation?
