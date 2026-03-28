# MenuStatus

macOS menu bar app that monitors the public status of any service using [Atlassian Statuspage](https://www.atlassian.com/software/statuspage) or [incident.io](https://incident.io) at a glance.

Ships with OpenAI and Anthropic built in. Add any compatible service (GitHub, Cloudflare, 1Password, Twilio, ...) by pasting its status page URL.

## Features

- Menu bar only (`LSUIElement`) — no Dock icon
- Configurable polling interval (30s – 10min, default 60s)
- Adaptive menu bar icon: system template when operational, colored on degradation
- Per-provider tab view with overall status, active incidents, and component timelines
- 90-day uptime bar per component with hover tooltips
- Grouped component sections (incident.io providers) with collapsible detail
- Settings window: refresh interval, launch at login, enable/disable providers
- Add custom providers by URL with auto-detection of platform and service name
- Import/export provider configurations as JSON for sharing

## Supported Platforms

| Platform | Examples | Detection |
|----------|----------|-----------|
| Atlassian Statuspage | Anthropic, GitHub, Cloudflare, 1Password, Twilio | SVG fill colors in status page HTML |
| incident.io | OpenAI | Next.js `__next_f.push` JSON blocks |

Both platforms expose a standard `/api/v2/summary.json` endpoint. Services with custom-built status pages (Google Cloud, AWS) are not supported.

## Requirements

- macOS 14.0+
- Xcode 15+ command line tools
- [Tuist](https://tuist.io) installed locally

## Quick Start

```bash
# Build and launch (generates project, builds, opens app)
./run-menubar.sh

# Stop the running instance
./stop-menubar.sh
```

Or manually:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme MenuStatus \
  -configuration Debug \
  -derivedDataPath .build
```

## Tests

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme MenuStatus \
  -configuration Debug \
  -derivedDataPath .build
```

## Adding a Provider

### In the app

1. Open Settings (gear icon in the menu)
2. Enter a status page URL (e.g. `https://www.githubstatus.com`)
3. The app auto-detects the platform, fetches the service name, and adds it

### Via config import

Share or import a JSON file:

```json
{
  "providers": [
    { "name": "GitHub", "url": "https://www.githubstatus.com" },
    { "name": "Cloudflare", "url": "https://www.cloudflarestatus.com" }
  ]
}
```

Platform is auto-detected on import. Custom provider configs are stored in `~/Library/Application Support/MenuStatus/providers.json`.

## Architecture

```
ProviderConfigStore ──providers──► StatusStore ──@Observable──► SwiftUI Views
                                       │
StatusClient ──fetch & parse───────────┘
                                       │
                                  SettingsStore
                                  (UserDefaults)
```

| Layer | Files | Responsibility |
|-------|-------|----------------|
| **Models** | `StatusModels.swift` | `ProviderConfig`, `StatusPlatform`, API types, timeline builders |
| **Provider Config** | `ProviderConfigStore.swift` | Runtime provider list, persistence, auto-detection, import/export |
| **Client** | `StatusClient.swift` | Network requests, HTML parsing (incident.io / Atlassian Statuspage) |
| **Store** | `StatusStore.swift` | Observable state, polling, presentation derivation |
| **Settings** | `SettingsStore.swift`, `SettingsView.swift` | UserDefaults preferences, settings UI |
| **Views** | `MenuStatusApp.swift`, `StatusMenuContentView.swift`, `StatusRowViews.swift` | MenuBarExtra, tabs, component rows, uptime bars |

## Project Structure

```
.
├── Project.swift                # Tuist target definitions
├── Tuist.swift                  # Tuist config
├── Sources/
│   ├── StatusModels.swift       # ProviderConfig, platform, API types, timeline logic
│   ├── ProviderConfigStore.swift # Provider list management, persistence, detection
│   ├── StatusClient.swift       # Network + HTML parsing
│   ├── StatusStore.swift        # Observable state + polling
│   ├── SettingsStore.swift      # UserDefaults preferences
│   ├── SettingsView.swift       # Settings window UI with add/remove/import/export
│   ├── MenuStatusApp.swift      # App entry, MenuBarExtra, icon rendering
│   ├── StatusMenuContentView.swift  # Menu content + tabs
│   └── StatusRowViews.swift     # Component rows, uptime bars, incidents
├── Tests/
│   ├── StatusClientTests.swift
│   └── StatusStoreTests.swift
├── run-menubar.sh
└── stop-menubar.sh
```

## Notes

- Generated `.xcodeproj` / `.xcworkspace` and build outputs (`.build/`, `Derived/`) are gitignored — do not edit by hand.
- The app only reads public HTTPS status endpoints and requires no API keys or secrets.
