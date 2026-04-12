# AI Stupid Level Dedicated Page

## Goal

Add a dedicated "Benchmark" page to the MenuStatus popover that consolidates all AI Stupid Level data into a single, scrollable dashboard. Replace the current scattered display (header bars + per-tab benchmark sections) with a unified view, while keeping a one-line summary in each provider tab as an entry point.

## Entry Points

1. **Tab grid**: A special "Benchmark" tab after all provider tabs, visually separated by a thin divider. Uses `chart.bar.xaxis` icon + "Benchmark" label, no status dot, lighter style than provider tabs.
2. **GlobalIndexBar**: The existing AI Index bar becomes clickable. Hover shows `Color.primary.opacity(0.05)` background + a `chevron.right` affordance on the right. Click navigates to the benchmark page.
3. **Per-tab summary line**: The simplified BenchmarkSection in each provider tab shows a one-line summary with a chevron; clicking it also navigates to the benchmark page.

## Navigation Architecture

### MenuSelection enum

```swift
enum MenuSelection: Hashable {
    case provider(ProviderConfig)
    case benchmark
}
```

Replaces `@State private var selectedProvider: ProviderConfig?` with `@State private var selection: MenuSelection?`.

`activeSelection` computed property: if current selection is valid (provider still in enabled list, or `.benchmark`), return it; otherwise fallback to `.provider(enabledProviders.first)` if available, or `nil` (shows loading placeholder).

`selectedProviderContent` dispatches on `activeSelection`:
- `.benchmark` → `AIStupidLevelPageView`
- `.provider(let p)` → existing `ProviderSectionView` logic (unchanged)

### Tab grid changes

`ProviderTabGrid` gains parameters: `showBenchmarkTab: Bool`, `isBenchmarkSelected: Bool`, `onSelectBenchmark: () -> Void`.

Benchmark tab renders after all providers, preceded by a subtle `Divider`. It occupies the leftmost cell of a new row (remaining cells are `Color.clear` placeholders). Style: `.secondary` foreground, `chart.bar.xaxis` icon, "Benchmark" text, same hover behavior as provider tabs but no status dot.

### Height & scroll strategy

`contentHeights` key changes from `ProviderConfig` to `MenuSelection`. However, the `.benchmark` case **always uses ScrollView** — it skips the height-measurement optimization entirely. The benchmark page is expected to be long and dynamically sized; the cost of measuring then removing ScrollView is not worth the risk.

For `.provider` cases, existing height caching and conditional ScrollView logic remains unchanged.

## Benchmark Page Content

`AIStupidLevelPageView` — a new file. Receives `benchmarkStore: AIStupidLevelStore` and `onNavigateToProvider: (ProviderConfig) -> Void`. Always rendered inside a ScrollView by the parent.

Six collapsible sections, each using a custom disclosure pattern (Button + chevron + `@State isExpanded`). Chevron hover follows existing spec: `tertiary` → `primary` + `scaleEffect(1.2)`, `easeInOut(duration: 0.15)`.

### Section 1: Global Index Detail (default: expanded)

- Large current score (20pt semibold rounded) + trend arrow + trend text
- History chart: Canvas-drawn line chart, ~60pt tall, using `globalIndex.history`
- Next scheduled batch run time (from `batchStatus.nextScheduledRun`), formatted as relative or absolute time

### Section 2: Model Ranking (default: expanded)

- All models from `scores` array, sorted by `currentScore` descending
- Each row: rank number, model name, vendor chip (small colored label), score bar with confidence interval, integer score, trend icon
- Tap a row to expand its history sparkline (triggers `loadHistoryIfNeeded`)
- Top filter: "All" + per-vendor tag buttons for quick filtering

### Section 3: Vendor Comparison (default: collapsed)

- One row per vendor: name, model count, average score, Trust score (from `providerReliability`), alert count
- Sorted by average score descending
- Tap a vendor row → `onNavigateToProvider` callback switches to that provider's tab

### Section 4: Recommendations (default: collapsed)

- Three cards in an HStack (or VStack if narrow): Best for Code, Most Reliable, Fastest Response
- Each card: category label, model name, vendor, reason text, score
- Data from `recommendations` (bestForCode, mostReliable, fastestResponse)

### Section 5: Alerts (default: collapsed, title shows count badge when non-empty)

- Full list of `dashboardAlerts`
- Each row: severity icon with color, alert name, provider, timestamp
- Sorted by recency

### Section 6: Degradations (default: collapsed, title shows count badge when non-empty)

- Full list of `degradations`
- Each row: model name, provider, degradation magnitude, current score vs baseline
- Sorted by magnitude descending

## Changes to Existing Benchmark Display

### GlobalIndexBar (BenchmarkViews.swift)

- Wrapped in a Button
- `onTap: () -> Void` callback added
- Hover: background `Color.primary.opacity(0.05)` on `RoundedRectangle(cornerRadius: 8, style: .continuous)`
- Right side: `chevron.right` icon, font size 10, `.tertiary` color
- Accessibility: label "Open Benchmark dashboard"

### BenchmarkSection (BenchmarkViews.swift)

Simplified to a single non-expandable summary row:
- "Model Benchmarks" label + summary text ("3 models · avg 72 · 1 alert")
- Right side: `chevron.right`
- Click → `onNavigateToBenchmark()` callback
- All expanded content removed: no more model rows, tag lines, reliability, alerts, degradation lines inside provider tabs

### BenchmarkInsightsHeaderBar (BenchmarkInsightsViews.swift)

Removed entirely. Its content (alert count, next run time, best model recommendation) moves into the benchmark page's Global Index Detail section.

## File Changes

| File | Change |
|------|--------|
| `Sources/AIStupidLevelPageView.swift` | **New**. Benchmark dashboard with 6 collapsible sections. |
| `Sources/StatusMenuContentView.swift` | `selectedProvider` → `MenuSelection`; `selectedProviderContent` adds `.benchmark` branch; benchmark page always in ScrollView; `GlobalIndexBar` gets `onTap`; remove `BenchmarkInsightsHeaderBar` rendering. |
| `Sources/BenchmarkViews.swift` | `GlobalIndexBar` adds tap/hover/chevron. `BenchmarkSection` simplified to summary row with navigation callback. |
| `Sources/BenchmarkInsightsViews.swift` | Delete file. |
| `Sources/StatusRowViews.swift` | `ProviderSectionView` passes `onNavigateToBenchmark` to simplified `BenchmarkSection`. |

### Unchanged

- `AIStupidLevelStore.swift` — data layer, all APIs and vendor filtering methods reused as-is
- `AIStupidLevelClient.swift` — network layer unchanged
- `AIStupidLevelModels.swift` / `AIStupidLevelAnalyticsModels.swift` — models unchanged
- `MenuStatusApp.swift` — entry point unchanged

## Data Flow

```
AIStupidLevelStore (existing, unchanged)
  ├── AIStupidLevelPageView (new, reads all store properties)
  ├── GlobalIndexBar (modified, adds onTap)
  ├── BenchmarkSection (modified, simplified to summary)
  └── BenchmarkInsightsHeaderBar (deleted)
```

No new network requests. All data already fetched in `refreshNow()`. On-demand model history via `loadHistoryIfNeeded` unchanged.

## Design Review Notes

Per external review feedback:

1. **Benchmark tab visual separation**: Must not look like another provider. Separated by divider, lighter style, analytics icon, "Benchmark" label with aggregation semantics.
2. **Always ScrollView for benchmark page**: Skip height measurement optimization. Content is inherently long and dynamic.
3. **GlobalIndexBar click affordance**: Hover background + chevron + accessibility label. Not a silent invisible button.
4. **Provider tab BenchmarkSection**: Simplified to one-line summary (option b). Not removed entirely (loses context) and not kept as-is (duplicates the dedicated page).
5. **Window height jumps**: Benchmark page is always scrollable with fixed max height, so switching between provider (possibly short) and benchmark (always tall) won't cause the popover to resize dramatically — both are capped at `maxVisibleContentHeight`.
