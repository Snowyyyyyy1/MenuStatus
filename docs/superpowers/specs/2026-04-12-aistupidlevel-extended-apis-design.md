# Design: AI Stupid Level extended public APIs (MenuStatus)

**Date:** 2026-04-12  
**Status:** Draft for implementation planning  
**Scope:** Integrate additional `aistupidlevel.info` JSON endpoints into the existing menubar popover: **global insights (B)** and **per-provider tab enrichment (A)**. Both are in product scope; delivery may be split across two implementation PRs for risk control.

## Background

MenuStatus currently polls:

- `GET /api/dashboard/scores`
- `GET /api/dashboard/global-index`

The public `scores` list exposes a fixed small set of models (order of tens). Richer value for users comes from **parallel analytics and operational endpoints** that are also publicly reachable with HTTP 200.

## Goals

1. Show **aggregated benchmark intelligence** in the popover header (near the existing global index bar), without breaking header height measurement or scroll behavior.
2. Show **vendor-scoped** alerts, degradations, and recommendation context inside each provider’s **Model Benchmarks** section.
3. Preserve **resilient decoding** and **isolated fetch failure** semantics (one bad endpoint must not clear scores/global index).
4. Add **on-demand** per-model history where it adds clear value, without N+1 network storms on every open.

## Non-goals

- Authenticated or undocumented routes; enterprise-only datasets.
- Replacing the menu bar icon state with benchmark volatility.
- Using `GET /api/dashboard/cached` in the first implementation tranche (optional optimization later; shape may drift).
- Polling `GET /api/models/:id/history` for every model on every refresh.

## User-facing design

### Section A — Global (“B”)

**Placement:** Directly below `GlobalIndexBar`, still inside the same header `VStack` that feeds `headerHeight` via `GeometryReader`, with existing `Divider` rhythm unchanged.

**Content (summary-first):**

- **Alerts:** Count of active alerts (and highest severity badge if any). Tapping opens the site in the default browser (`NSWorkspace.shared.open`), e.g. `https://aistupidlevel.info/`, unless a more specific stable URL exists for alerts (prefer site root if none).
- **Batch status:** Next scheduled run time from `batch-status` when present; hide row if missing.
- **Recommendations:** One short line derived from `recommendations` (e.g. best-for-code name + vendor), not full prose.
- **Provider reliability (optional in v1):** If space allows, a single horizontal row of compact chips (`provider` + `trustScore`); otherwise defer to tab scope or phase 2 of implementation.

**Failure behavior for “extension” payloads:** **Silent omission** of extension-only UI when those requests fail or decode partially; do not replace or blank the main global index or scores. Optional future: a single tertiary “扩展数据暂不可用” line — explicitly out of scope for v1.

### Section B — Per provider tab (“A”)

**Placement:** Inside the existing collapsible `BenchmarkSection` for providers with `aiStupidLevelVendor` set.

**Content:**

- **Vendor-filtered alerts** from the global `alerts` list (`provider` / `vendor` case-insensitive match to `aiStupidLevelVendor`).
- **Vendor-filtered degradations** from `degradations` (match on provider/vendor fields returned by API).
- **Recommendation hook:** If any `recommendations` entry’s vendor matches the tab, show one line (e.g. reason / rank) with link-out for detail.
- **Per-model history:** Only after explicit user action (e.g. “趋势” or row disclosure). One in-flight request per model id; short-lived cache in store keyed by model id.

**Benchmark-only tabs** (`platform == .aiStupidLevelOnly`): Same benchmark UI rules apply; ensure filtering still works when the tab is benchmark-only.

## Data flow and architecture

### Client (`AIStupidLevelClient`)

Add typed fetch + decode methods (mirroring existing style):

- `fetchAlerts()`, `fetchRecommendations()`, `fetchBatchStatus()`, `fetchProviderReliability()`, `fetchDegradations()`
- `fetchModelHistory(modelId:)` on demand

Use the same `baseURL`, `URLSession`, and HTTP success range as today. Each method throws independently.

### Store (`AIStupidLevelStore`)

- Extend `@Observable` state with properties for each payload above, plus `historyByModelID: [String: ModelHistoryPayload]` (or equivalent) with optional TTL.
- `refreshNow()` uses structured concurrency to load **scores**, **global-index**, and **all extension GETs** in parallel; each assignment wrapped so a failure in extension data does not prevent updating `scores` / `globalIndex`.
- `isLoading` remains a single gate for “full refresh in progress” unless we later split “core vs extension” for UI shimmer — out of scope for v1.

### Views

- New small SwiftUI component(s) under a focused file (e.g. extend `BenchmarkViews.swift` or add `BenchmarkInsightsViews.swift`) for header insights to avoid bloating `StatusMenuContentView` beyond wiring.
- **Do not** attach `.task` or heavy modifiers to `MenuBarExtra` label (existing project constraint).
- Respect existing hover / animation conventions (`easeInOut(0.15)`, no `ButtonStyle` for footer-like patterns if similar controls appear).

### Polling

- Keep default poll interval aligned with existing benchmark polling (e.g. 300s) unless profiling shows excessive load; extension endpoints add payload size — monitor in plan phase.

## Models

- New `Decodable` types per endpoint with **optional fields** and safe defaults for enum-like strings (same pattern as `BenchmarkTrend` / `BenchmarkStatus`).
- Ignore unknown JSON keys via standard `JSONDecoder` behavior; avoid strict coupling to marketing copy fields.

## Testing

- **Client tests:** Inline JSON fixtures for each new response type, asserting decode succeeds on real-shaped samples (can be trimmed fixtures).
- **Store tests:** Vendor filtering helpers (e.g. alerts/degradations for `openai` vs `anthropic`).

## Implementation phasing (engineering, not product)

Product includes **both** header insights and tab enrichment. Engineering may land in two steps:

1. Client + store + models + tests for all fetches; header insights UI.
2. Tab UI + on-demand history + any reliability chips deferred from step 1.

## Open risks

- Upstream JSON shape drift → mitigated by optional decoding and tests.
- Popover height growth → mitigated by summary-first UI and browser handoff for depth.

## Approval

- Sections 1–2 reviewed in conversation; user confirmed continuation (“可以”).
- Extension fetch failure UX: **silent omission** for v1.
