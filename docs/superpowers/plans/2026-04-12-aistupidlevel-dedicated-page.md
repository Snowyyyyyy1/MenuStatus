# AI Stupid Level Dedicated Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dedicated "Benchmark" tab/page that consolidates all AI Stupid Level data, simplify existing scattered benchmark UI to entry-point summaries.

**Architecture:** Introduce `MenuSelection` enum to unify tab selection state. New `AIStupidLevelPageView` with 6 collapsible sections. Benchmark page always uses ScrollView. Existing `BenchmarkSection` simplified to one-line summary; `BenchmarkInsightsHeaderBar` deleted.

**Tech Stack:** SwiftUI, Canvas (charts), @Observable, Tuist + xcodebuild

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/StatusMenuContentView.swift` | Modify | `MenuSelection` enum, selection state, content dispatch, height/scroll logic, GlobalIndexBar tap wiring, remove InsightsHeaderBar |
| `Sources/AIStupidLevelPageView.swift` | Create | Dedicated benchmark page with 6 collapsible sections |
| `Sources/BenchmarkViews.swift` | Modify | `GlobalIndexBar` adds tap callback + hover + chevron; `BenchmarkSection` simplified to summary row |
| `Sources/BenchmarkInsightsViews.swift` | Delete | Content moved into dedicated page |
| `Sources/StatusRowViews.swift` | Modify | Pass `onNavigateToBenchmark` to simplified `BenchmarkSection` |

Unchanged: `AIStupidLevelStore.swift`, `AIStupidLevelClient.swift`, `AIStupidLevelModels.swift`, `AIStupidLevelAnalyticsModels.swift`, `MenuStatusApp.swift`.

---

### Task 1: MenuSelection enum + selection state

**Files:**
- Modify: `Sources/StatusMenuContentView.swift:1-30` (state declarations)

- [ ] **Step 1: Add MenuSelection enum and replace selectedProvider**

At the top of `StatusMenuContentView.swift`, add the enum before `StatusMenuContentView` and change the state:

```swift
enum MenuSelection: Hashable {
    case provider(ProviderConfig)
    case benchmark
}
```

In `StatusMenuContentView`, replace:

```swift
@State private var selectedProvider: ProviderConfig?
@State private var contentHeights: [ProviderConfig: CGFloat] = [:]
```

with:

```swift
@State private var selection: MenuSelection?
@State private var contentHeights: [MenuSelection: CGFloat] = [:]
```

- [ ] **Step 2: Update activeProvider to activeSelection**

Replace the `activeProvider` computed property:

```swift
private var activeProvider: ProviderConfig? {
    if let selectedProvider, enabledProviders.contains(selectedProvider) {
        return selectedProvider
    }
    return enabledProviders.first
}
```

with:

```swift
private var activeSelection: MenuSelection {
    if let selection {
        switch selection {
        case .provider(let p) where enabledProviders.contains(p):
            return selection
        case .benchmark:
            return selection
        default:
            break
        }
    }
    if let first = enabledProviders.first {
        return .provider(first)
    }
    return .benchmark
}
```

- [ ] **Step 3: Update all references to activeProvider and selectedProvider**

In `activeContentHeight`:

```swift
private var activeContentHeight: CGFloat {
    contentHeights[activeSelection] ?? .infinity
}
```

In `needsScroll`, add benchmark bypass:

```swift
private var needsScroll: Bool {
    if case .benchmark = activeSelection { return true }
    return activeContentHeight > maxVisibleContentHeight
}
```

In `measuredContent`, update the height caching:

```swift
private var measuredContent: some View {
    selectedProviderContent
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size.height, initial: true) { _, h in
                        contentHeights[activeSelection] = h
                        if !initialMeasurementDone { initialMeasurementDone = true }
                    }
            }
        }
}
```

- [ ] **Step 4: Update selectedProviderContent dispatch**

Replace the existing `selectedProviderContent`:

```swift
@ViewBuilder
private var selectedProviderContent: some View {
    switch activeSelection {
    case .benchmark:
        AIStupidLevelPageView(benchmarkStore: benchmarkStore) { provider in
            selection = .provider(provider)
        }
    case .provider(let provider):
        if provider.hasStatusPage, let summary = store.summaries[provider] {
            ProviderSectionView(
                provider: provider,
                summary: summary,
                store: store,
                benchmarkStore: benchmarkStore,
                settings: store.settings,
                onNavigateToBenchmark: { selection = .benchmark }
            )
        } else if !provider.hasStatusPage {
            ProviderSectionView(
                provider: provider,
                summary: nil,
                store: store,
                benchmarkStore: benchmarkStore,
                settings: store.settings,
                onNavigateToBenchmark: { selection = .benchmark }
            )
        } else {
            loadingPlaceholder
        }
    }
}
```

Note: `ProviderSectionView` gets a new `onNavigateToBenchmark` parameter — this will be wired in Task 5.

- [ ] **Step 5: Update ProviderTabGrid call site**

Replace the existing `ProviderTabGrid(...)` block:

```swift
ProviderTabGrid(
    providers: enabledProviders,
    activeSelection: activeSelection,
    summaries: store.summaries,
    settings: store.settings,
    onSelectProvider: { provider in
        selection = .provider(provider)
    },
    onSelectBenchmark: {
        selection = .benchmark
    }
)
```

- [ ] **Step 6: Wire GlobalIndexBar tap and remove BenchmarkInsightsHeaderBar**

Replace the GlobalIndexBar + InsightsHeaderBar block:

```swift
if let globalIndex = benchmarkStore.globalIndex {
    GlobalIndexBar(index: globalIndex) {
        selection = .benchmark
    }
    Divider()
}
```

Remove the `hasBenchmarkInsights` computed property and the entire `BenchmarkInsightsHeaderBar` block (lines 49-52 and 78-81).

- [ ] **Step 7: Build and verify compilation**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build 2>&1 | tail -5
```

Expected: Build will fail because `AIStupidLevelPageView`, updated `ProviderTabGrid`, updated `GlobalIndexBar`, and updated `ProviderSectionView` don't exist yet. This is expected — we're building incrementally.

- [ ] **Step 8: Commit navigation scaffolding**

```bash
git add Sources/StatusMenuContentView.swift
git commit -m "refactor: introduce MenuSelection enum for tab navigation"
```

---

### Task 2: Update ProviderTabGrid with benchmark tab

**Files:**
- Modify: `Sources/StatusMenuContentView.swift:263-298` (ProviderTabGrid struct)

- [ ] **Step 1: Update ProviderTabGrid signature and add benchmark tab**

Replace the entire `ProviderTabGrid` struct:

```swift
private struct ProviderTabGrid: View {
    let providers: [ProviderConfig]
    let activeSelection: MenuSelection
    let summaries: [ProviderConfig: StatuspageSummary]
    let settings: SettingsStore
    let onSelectProvider: (ProviderConfig) -> Void
    let onSelectBenchmark: () -> Void

    private let columns = 3

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<providerRowCount, id: \.self) { rowIndex in
                GridRow {
                    ForEach(0..<columns, id: \.self) { col in
                        let index = rowIndex * columns + col
                        if index < providers.count {
                            let provider = providers[index]
                            ProviderTab(
                                name: settings.displayName(for: provider),
                                isSelected: activeSelection == .provider(provider),
                                indicator: summaries[provider]?.status.indicator
                            ) {
                                onSelectProvider(provider)
                            }
                        } else {
                            Color.clear.gridCellUnsizedAxes(.vertical)
                        }
                    }
                }
            }

            Divider()
                .gridCellColumns(columns)
                .padding(.vertical, 2)

            GridRow {
                BenchmarkTab(
                    isSelected: activeSelection == .benchmark,
                    action: onSelectBenchmark
                )
                Color.clear.gridCellUnsizedAxes(.vertical)
                Color.clear.gridCellUnsizedAxes(.vertical)
            }
        }
    }

    private var providerRowCount: Int {
        (providers.count + columns - 1) / columns
    }
}
```

- [ ] **Step 2: Add BenchmarkTab view**

Add after `ProviderTabGrid`, before `ProviderTab`:

```swift
private struct BenchmarkTab: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10))
                Text("Benchmark")
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.1) : isHovered ? Color.primary.opacity(0.05) : .clear)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add Sources/StatusMenuContentView.swift
git commit -m "feat: add Benchmark tab to provider tab grid"
```

---

### Task 3: Update GlobalIndexBar with tap + hover + chevron

**Files:**
- Modify: `Sources/BenchmarkViews.swift:6-50` (GlobalIndexBar)

- [ ] **Step 1: Add onTap callback and hover state to GlobalIndexBar**

Replace the entire `GlobalIndexBar` struct:

```swift
struct GlobalIndexBar: View {
    let index: GlobalIndex
    let onTap: () -> Void

    @State private var isHovered = false

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
        Button(action: onTap) {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.05) : .clear)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open Benchmark dashboard")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Sources/BenchmarkViews.swift
git commit -m "feat: make GlobalIndexBar tappable with hover and chevron"
```

---

### Task 4: Simplify BenchmarkSection to summary row

**Files:**
- Modify: `Sources/BenchmarkViews.swift:82-193` (BenchmarkSection)

- [ ] **Step 1: Replace BenchmarkSection with simplified summary row**

Replace the entire `BenchmarkSection` struct (keep everything below it — `BenchmarkModelRow`, sparklines, `ScoreBar`):

```swift
struct BenchmarkSection: View {
    let summary: BenchmarkVendorSummary
    let onNavigateToBenchmark: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onNavigateToBenchmark) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Model Benchmarks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(summaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isHovered ? .primary : .tertiary)
                    .scaleEffect(isHovered ? 1.2 : 1.0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
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
```

Note: `BenchmarkModelRow`, `ModelHistorySparkline`, `ScoreBar` remain unchanged — they will be reused by the dedicated page.

- [ ] **Step 2: Commit**

```bash
git add Sources/BenchmarkViews.swift
git commit -m "refactor: simplify BenchmarkSection to one-line summary with navigation"
```

---

### Task 5: Update ProviderSectionView to pass onNavigateToBenchmark

**Files:**
- Modify: `Sources/StatusRowViews.swift:10-67`

- [ ] **Step 1: Add onNavigateToBenchmark parameter and update BenchmarkSection call**

Add the parameter to `ProviderSectionView`:

```swift
struct ProviderSectionView: View {
    let provider: ProviderConfig
    let summary: StatuspageSummary?
    let store: StatusStore
    let benchmarkStore: AIStupidLevelStore
    let settings: SettingsStore
    let onNavigateToBenchmark: () -> Void
```

Remove the `benchmarkExpanded` property and `toggleBenchmarkExpanded()` method (lines 35-45) — no longer needed since `BenchmarkSection` is no longer expandable.

Update the `BenchmarkSection` call in `body`:

```swift
if let benchmarkSummary {
    if summary != nil {
        Divider().padding(.horizontal, 16).padding(.vertical, 4)
    }
    BenchmarkSection(
        summary: benchmarkSummary,
        onNavigateToBenchmark: onNavigateToBenchmark
    )
}
```

- [ ] **Step 2: Remove benchmarkSectionExpanded from SettingsStore if it was only used here**

Check if `benchmarkSectionExpanded` in `SettingsStore` is used elsewhere. If only by `ProviderSectionView`, it can be removed. If used elsewhere, leave it.

```bash
cd /Users/snowyy/Code/MenuStatus && rg "benchmarkSectionExpanded" Sources/
```

If only in `StatusRowViews.swift` and `SettingsStore.swift`, remove the property from `SettingsStore`.

- [ ] **Step 3: Build to check compilation state**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build 2>&1 | tail -5
```

Expected: Still fails because `AIStupidLevelPageView` doesn't exist yet.

- [ ] **Step 4: Commit**

```bash
git add Sources/StatusRowViews.swift Sources/SettingsStore.swift
git commit -m "refactor: wire onNavigateToBenchmark through ProviderSectionView"
```

---

### Task 6: Delete BenchmarkInsightsHeaderBar

**Files:**
- Delete: `Sources/BenchmarkInsightsViews.swift`

- [ ] **Step 1: Delete the file**

```bash
rm Sources/BenchmarkInsightsViews.swift
```

All references to `BenchmarkInsightsHeaderBar` were already removed from `StatusMenuContentView` in Task 1 Step 6.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "chore: remove BenchmarkInsightsHeaderBar (content moved to dedicated page)"
```

---

### Task 7: Create AIStupidLevelPageView — Global Index section

**Files:**
- Create: `Sources/AIStupidLevelPageView.swift`

- [ ] **Step 1: Create file with page skeleton and Global Index section**

```swift
import SwiftUI

struct AIStupidLevelPageView: View {
    let benchmarkStore: AIStupidLevelStore
    let onNavigateToProvider: (ProviderConfig) -> Void

    @State private var globalIndexExpanded = true
    @State private var rankingExpanded = true
    @State private var vendorComparisonExpanded = false
    @State private var recommendationsExpanded = false
    @State private var alertsExpanded = false
    @State private var degradationsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = benchmarkStore.globalIndex {
                CollapsibleSection(
                    title: "Global Index",
                    isExpanded: $globalIndexExpanded
                ) {
                    GlobalIndexDetailView(
                        index: index,
                        batchStatus: benchmarkStore.batchStatus
                    )
                }
            }

            if !benchmarkStore.scores.isEmpty {
                CollapsibleSection(
                    title: "Model Ranking",
                    isExpanded: $rankingExpanded
                ) {
                    ModelRankingView(
                        scores: benchmarkStore.scores,
                        historyByModelID: benchmarkStore.historyByModelID,
                        onLoadHistory: { benchmarkStore.loadHistoryIfNeeded(modelId: $0) }
                    )
                }
            }

            vendorComparisonSection
            recommendationsSection
            alertsSection
            degradationsSection
        }
        .padding(.bottom, 8)
    }
}
```

- [ ] **Step 2: Add CollapsibleSection helper**

```swift
private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    let badge: Int?
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false

    init(
        title: String,
        isExpanded: Binding<Bool>,
        badge: Int? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self._isExpanded = isExpanded
        self.badge = badge
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .tertiary)
                        .scaleEffect(isHovered ? 1.2 : 1.0)

                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                    }

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
                content()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            Divider().padding(.horizontal, 12)
        }
    }
}
```

- [ ] **Step 3: Add GlobalIndexDetailView**

```swift
private struct GlobalIndexDetailView: View {
    let index: GlobalIndex
    let batchStatus: DashboardBatchStatusData?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(Int(index.current.globalScore.rounded()))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Image(systemName: trendSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(trendColor)

                Text(index.trend.capitalized)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                Spacer()

                if let totalModels = index.totalModels {
                    Text("\(totalModels) models")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            LargeIndexChart(points: index.history.reversed())
                .frame(height: 60)

            if let nextRun = formattedNextRun {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                    Text("Next benchmark: \(nextRun)")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
        }
    }

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

    private var formattedNextRun: String? {
        guard let raw = batchStatus?.nextScheduledRun else { return nil }
        let parser = ISO8601DateFormatter()
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct LargeIndexChart: View {
    let points: [GlobalIndexPoint]

    var body: some View {
        Canvas { context, size in
            guard points.count >= 2 else { return }
            let scores = points.map(\.globalScore)
            let minV = (scores.min() ?? 0) - 2
            let maxV = (scores.max() ?? 100) + 2
            let range = max(1, maxV - minV)

            var fillPath = Path()
            var linePath = Path()
            for (i, score) in scores.enumerated() {
                let x = CGFloat(i) / CGFloat(scores.count - 1) * size.width
                let y = size.height - CGFloat((score - minV) / range) * size.height
                if i == 0 {
                    fillPath.move(to: CGPoint(x: x, y: size.height))
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                    linePath.move(to: CGPoint(x: x, y: y))
                } else {
                    fillPath.addLine(to: CGPoint(x: x, y: y))
                    linePath.addLine(to: CGPoint(x: x, y: y))
                }
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()

            context.fill(fillPath, with: .color(.accentColor.opacity(0.1)))
            context.stroke(
                linePath,
                with: .color(.accentColor.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Sources/AIStupidLevelPageView.swift
git commit -m "feat: add AIStupidLevelPageView with Global Index section"
```

---

### Task 8: Model Ranking section

**Files:**
- Modify: `Sources/AIStupidLevelPageView.swift`

- [ ] **Step 1: Add ModelRankingView**

Append to `AIStupidLevelPageView.swift`:

```swift
private struct ModelRankingView: View {
    let scores: [BenchmarkScore]
    let historyByModelID: [String: ModelHistoryPayload]
    let onLoadHistory: (String) -> Void

    @State private var vendorFilter: String?
    @State private var expandedModelID: String?

    private var uniqueVendors: [String] {
        Array(Set(scores.map(\.provider))).sorted()
    }

    private var filteredScores: [BenchmarkScore] {
        let sorted = scores.sorted { $0.currentScore > $1.currentScore }
        guard let filter = vendorFilter else { return sorted }
        return sorted.filter { $0.provider.caseInsensitiveCompare(filter) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                FilterTag(label: "All", isSelected: vendorFilter == nil) {
                    vendorFilter = nil
                }
                ForEach(uniqueVendors, id: \.self) { vendor in
                    FilterTag(label: vendor.capitalized, isSelected: vendorFilter == vendor) {
                        vendorFilter = vendorFilter == vendor ? nil : vendor
                    }
                }
            }

            ForEach(Array(filteredScores.enumerated()), id: \.element.id) { rank, score in
                RankedModelRow(
                    rank: rank + 1,
                    score: score,
                    isExpanded: expandedModelID == score.id,
                    history: historyByModelID[score.id]
                ) {
                    if expandedModelID == score.id {
                        expandedModelID = nil
                    } else {
                        expandedModelID = score.id
                        onLoadHistory(score.id)
                    }
                }
            }
        }
    }
}

private struct FilterTag: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct RankedModelRow: View {
    let rank: Int
    let score: BenchmarkScore
    let isExpanded: Bool
    let history: ModelHistoryPayload?
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Text("#\(rank)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, alignment: .trailing)

                    Text(score.name)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 140, alignment: .leading)

                    VendorChip(vendor: score.provider)

                    ScoreBar(
                        score: score.currentScore,
                        lower: score.confidenceLower,
                        upper: score.confidenceUpper,
                        color: score.status.color
                    )
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let history {
                ModelHistorySparkline(points: history.history)
                    .frame(height: 20)
                    .padding(.leading, 32)
            }
        }
    }
}

private struct VendorChip: View {
    let vendor: String

    var body: some View {
        Text(vendor.prefix(3).uppercased())
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(chipColor)
            )
    }

    private var chipColor: Color {
        switch vendor.lowercased() {
        case "openai": return .green
        case "anthropic": return .orange
        case "google": return .blue
        case "xai": return .purple
        case "deepseek": return .cyan
        case "kimi": return .pink
        case "glm": return .indigo
        default: return .gray
        }
    }
}
```

Note: `ScoreBar` and `ModelHistorySparkline` are already defined in `BenchmarkViews.swift`. Since they're `private`, they need to be made `internal` (remove `private`) or duplicated. The cleaner approach: change `ScoreBar` from `private` to default (`internal`) in `BenchmarkViews.swift`, and similarly for `ModelHistorySparkline`.

- [ ] **Step 2: Make ScoreBar and ModelHistorySparkline internal**

In `Sources/BenchmarkViews.swift`, change:
- `private struct ScoreBar` → `struct ScoreBar`
- `private struct ModelHistorySparkline` → `struct ModelHistorySparkline`

- [ ] **Step 3: Commit**

```bash
git add Sources/AIStupidLevelPageView.swift Sources/BenchmarkViews.swift
git commit -m "feat: add Model Ranking section with vendor filter and expandable history"
```

---

### Task 9: Vendor Comparison, Recommendations, Alerts, Degradations sections

**Files:**
- Modify: `Sources/AIStupidLevelPageView.swift`

- [ ] **Step 1: Add remaining section builders to AIStupidLevelPageView**

Add these computed properties inside `AIStupidLevelPageView`:

```swift
@ViewBuilder
private var vendorComparisonSection: some View {
    let rows = benchmarkStore.providerReliability
    if !rows.isEmpty {
        CollapsibleSection(
            title: "Vendor Comparison",
            isExpanded: $vendorComparisonExpanded
        ) {
            VendorComparisonView(
                reliability: rows,
                scores: benchmarkStore.scores,
                onSelectVendor: { vendorName in
                    if let provider = findProvider(forVendor: vendorName) {
                        onNavigateToProvider(provider)
                    }
                }
            )
        }
    }
}

@ViewBuilder
private var recommendationsSection: some View {
    if let recs = benchmarkStore.recommendations,
       recs.bestForCode != nil || recs.mostReliable != nil || recs.fastestResponse != nil {
        CollapsibleSection(
            title: "Recommendations",
            isExpanded: $recommendationsExpanded
        ) {
            RecommendationsView(recommendations: recs)
        }
    }
}

@ViewBuilder
private var alertsSection: some View {
    let alerts = benchmarkStore.dashboardAlerts
    if !alerts.isEmpty {
        CollapsibleSection(
            title: "Alerts",
            isExpanded: $alertsExpanded,
            badge: alerts.count
        ) {
            AlertsListView(alerts: alerts)
        }
    }
}

@ViewBuilder
private var degradationsSection: some View {
    let items = benchmarkStore.degradations
    if !items.isEmpty {
        CollapsibleSection(
            title: "Degradations",
            isExpanded: $degradationsExpanded,
            badge: items.count
        ) {
            DegradationsListView(degradations: items)
        }
    }
}

private func findProvider(forVendor vendorName: String) -> ProviderConfig? {
    ProviderConfig.builtInProviders.first {
        $0.aiStupidLevelVendor?.caseInsensitiveCompare(vendorName) == .orderedSame
    }
}
```

- [ ] **Step 2: Add VendorComparisonView**

```swift
private struct VendorComparisonView: View {
    let reliability: [ProviderReliabilityRow]
    let scores: [BenchmarkScore]
    let onSelectVendor: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sortedRows) { row in
                Button { onSelectVendor(row.provider) } label: {
                    HStack(spacing: 8) {
                        VendorChip(vendor: row.provider)

                        Text(row.provider.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .frame(maxWidth: 80, alignment: .leading)

                        let summary = vendorSummary(for: row.provider)
                        Text("\(summary.count) models")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        Text("avg \(Int(summary.avg.rounded()))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)

                        Spacer()

                        if let trust = row.trustScore {
                            Text("Trust \(trust)")
                                .font(.system(size: 10))
                                .foregroundStyle(trust >= 70 ? .green : trust >= 40 ? .yellow : .red)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sortedRows: [ProviderReliabilityRow] {
        reliability.sorted { vendorSummary(for: $0.provider).avg > vendorSummary(for: $1.provider).avg }
    }

    private func vendorSummary(for vendor: String) -> (count: Int, avg: Double) {
        let matching = scores.filter { $0.provider.caseInsensitiveCompare(vendor) == .orderedSame }
        let avg = matching.isEmpty ? 0 : matching.map(\.currentScore).reduce(0, +) / Double(matching.count)
        return (matching.count, avg)
    }
}
```

- [ ] **Step 3: Add RecommendationsView**

```swift
private struct RecommendationsView: View {
    let recommendations: AnalyticsRecommendationsPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let slot = recommendations.bestForCode {
                RecommendationCard(category: "Best for Code", icon: "curlybraces", slot: slot)
            }
            if let slot = recommendations.mostReliable {
                RecommendationCard(category: "Most Reliable", icon: "shield.lefthalf.filled", slot: slot)
            }
            if let slot = recommendations.fastestResponse {
                RecommendationCard(category: "Fastest Response", icon: "bolt.fill", slot: slot)
            }
        }
    }
}

private struct RecommendationCard: View {
    let category: String
    let icon: String
    let slot: AnalyticsRecommendationSlot

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(category)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    if let name = slot.name {
                        Text(name)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if let vendor = slot.vendor {
                        VendorChip(vendor: vendor)
                    }
                }
                if let reason = slot.reason {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let score = slot.score {
                Text("\(Int(score.rounded()))")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }
}
```

- [ ] **Step 4: Add AlertsListView and DegradationsListView**

```swift
private struct AlertsListView: View {
    let alerts: [DashboardAlert]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(alerts) { alert in
                HStack(spacing: 8) {
                    Image(systemName: severityIcon(alert.severity))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(severityColor(alert.severity))
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(alert.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(alert.provider.capitalized)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if let time = alert.detectedAt {
                                Text("· \(time)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func severityIcon(_ severity: String?) -> String {
        switch severity?.lowercased() {
        case "critical": return "xmark.circle.fill"
        case "warning": return "exclamationmark.triangle.fill"
        default: return "info.circle.fill"
        }
    }

    private func severityColor(_ severity: String?) -> Color {
        switch severity?.lowercased() {
        case "critical": return .red
        case "warning": return .yellow
        default: return .blue
        }
    }
}

private struct DegradationsListView: View {
    let degradations: [AnalyticsDegradationItem]

    private var sorted: [AnalyticsDegradationItem] {
        degradations.sorted { ($0.dropPercentage ?? 0) > ($1.dropPercentage ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(sorted) { item in
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                        .frame(width: 14)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(item.modelName ?? "Unknown")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            if let vendor = item.provider {
                                VendorChip(vendor: vendor)
                            }
                        }
                        if let drop = item.dropPercentage {
                            HStack(spacing: 4) {
                                Text("↓\(String(format: "%.1f", drop))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.orange)
                                if let current = item.currentScore, let baseline = item.baselineScore {
                                    Text("\(Int(current.rounded())) ← \(Int(baseline.rounded()))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AIStupidLevelPageView.swift
git commit -m "feat: add Vendor Comparison, Recommendations, Alerts, Degradations sections"
```

---

### Task 10: Build, test, and launch

**Files:**
- All modified/created files

- [ ] **Step 1: Full build**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Fix any compilation errors**

If build fails, read errors and fix. Common issues:
- Missing access levels on reused types
- Parameter mismatches between call sites and new signatures
- Import statements

- [ ] **Step 3: Run tests**

```bash
cd /Users/snowyy/Code/MenuStatus && TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build 2>&1 | tail -20
```

Expected: All tests pass. Existing tests should not be affected since data layer is unchanged.

- [ ] **Step 4: Launch the app**

```bash
cd /Users/snowyy/Code/MenuStatus && ./run-menubar.sh
```

Expected: App launches, menu bar icon visible. Click to open popover. Verify:
- Provider tabs appear with "Benchmark" tab at the bottom after a divider
- Clicking "Benchmark" tab shows the dedicated page with collapsible sections
- Clicking GlobalIndexBar also navigates to the benchmark page
- Provider tabs still work normally
- Simplified BenchmarkSection in provider tabs shows one-line summary with chevron

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete AI Stupid Level dedicated benchmark page"
```
