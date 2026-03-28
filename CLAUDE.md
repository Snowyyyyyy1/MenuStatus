# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MenuStatus is a macOS menu bar app (LSUIElement) that monitors the public status of any service using Atlassian Statuspage or incident.io. Built-in providers: OpenAI, Anthropic. Users can add custom providers via URL in Settings.

## Build & Run

Requires macOS 14.0+, Xcode 15+ CLI tools, and Tuist installed locally. All Tuist commands need `TUIST_SKIP_UPDATE_CHECK=1` prefix.

```bash
# Run (generates, builds, and launches)
./run-menubar.sh

# Stop
./stop-menubar.sh

# Build only
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build

# Run tests
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

## Architecture

```
ProviderConfigStore ──providers──► StatusStore ──@Observable──► SwiftUI Views
                                       │
StatusClient ──fetch & parse───────────┘
                                       │
                                  SettingsStore
                                  (UserDefaults)
```

### Provider System

Providers are runtime-configured, not compile-time enums:

- **`ProviderConfig`** (in `StatusModels.swift`) — struct with `id`, `displayName`, `baseURL`, `platform`, `isBuiltIn`. API URL derived from `baseURL/api/v2/summary.json`. Hashable by `id`.
- **`ProviderConfigStore`** — manages built-in + custom providers. Custom providers persisted to `~/Library/Application Support/MenuStatus/providers.json`. Has `detect(url:)` for auto-detecting platform type and service name from a URL. Supports JSON import/export.
- **`StatusPlatform`** — `.atlassianStatuspage` (Anthropic, GitHub, Cloudflare, etc.) or `.incidentIO` (OpenAI). Determines HTML parsing strategy.

Adding a new built-in provider: add a static constant to `ProviderConfig` and include it in `builtInProviders`.

### Key Layers

- **`StatusClient`** — Stateless. `fetchSummary(for:)` and `fetchOfficialHistory(for:)` take `ProviderConfig`. HTML parsing dispatches by `platform`: incident.io parses Next.js `__next_f.push` JSON blocks; Atlassian Statuspage parses SVG `<rect>` fill colors.

- **`StatusStore`** — `@Observable`. Owns `summaries`, `componentTimelines`, `groupedSections` dictionaries keyed by `ProviderConfig`. `derivePresentationState()` is a pure static method: if official history has groups → `buildGroupedSections()`, otherwise → `buildFlatTimelines()`. Polls at `settings.refreshInterval`, only fetches enabled providers.

- **`StatusModels`** — Domain types. `ComponentTimeline` builds 90-day timelines from impact records or hex fill colors. `StatusIndicator` and `ComponentStatus` are `Comparable` by severity for worst-case aggregation. `IncidentStatus` is an enum (not raw String).

- **`SettingsStore`** — UserDefaults-backed. Stores `refreshInterval`, `launchAtLogin`, `disabledProviderIDs`. References `ProviderConfigStore` for provider list.

- **Views** — `MenuStatusApp` → `MenuBarExtra(.window)` → `StatusMenuContentView` (tabs + content) → `StatusRowViews` (components, uptime bars, incidents). Settings opened via `@Environment(\.openWindow)`. Menu bar icon: template when operational, colored SF Symbol when degraded.

## Menu Bar Icon

Uses `NSImage` with `isTemplate` flag. Operational state renders as system template icon (adapts to light/dark). Non-operational states use `paletteColors` with `isTemplate = false`. Icon shapes follow Anthropic's convention: `checkmark.circle`, `minus.square`, `exclamationmark.triangle`, `xmark.circle`, `wrench.and.screwdriver`. Separate `menuBarSymbol` (outline) vs `sfSymbol` (fill) properties on `StatusIndicator`.

## Testing

XCTest with `@testable import MenuStatus`. Tests cover: HTTP response validation, incident.io HTML parsing, Atlassian Statuspage HTML parsing, timeline building from impacts, presentation state derivation, group expansion logic. Parse tests use inline HTML fixtures.
