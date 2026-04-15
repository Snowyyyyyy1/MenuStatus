# MenuStatus

A native macOS menu bar app for supported public status pages and AI benchmark snapshots.

MenuStatus has two primary views:

- **Supported Status Pages** — parse public status pages built on **Atlassian Statuspage** and **incident.io**
- **AI Stupid Level** — check AI benchmark data including global index, model ranking, vendor comparison, alerts, recommendations, and degradations

[Download Latest DMG](https://github.com/Snowyyyyyy1/MenuStatus/releases/latest) · [Release Notes](https://github.com/Snowyyyyyy1/MenuStatus/releases) · [Build From Source](#build-from-source)

## Two Primary Views

### Supported Status Pages

MenuStatus is not a generic parser for arbitrary status sites. It currently supports two status-page platforms only:

- **Atlassian Statuspage**
- **incident.io**

Built-in providers include **OpenAI** and **Anthropic**. You can also add other compatible status-page URLs such as GitHub, Cloudflare, 1Password, Proton, and similar services built on those two formats.

From the menu bar you can:

- switch between providers quickly
- inspect grouped components and uptime bars
- view active incidents and recent history
- open a provider's official status page when you need the full context

### AI Stupid Level

MenuStatus also includes an **AI Stupid Level** view for quick benchmark snapshots from `aistupidlevel.info`.

It surfaces:

- global index and trend
- model ranking
- vendor comparison
- recommendations
- alerts
- degradations

This gives the app a second primary workflow alongside service-status tracking: checking whether model quality and reliability appear to be slipping.

## Screenshots

<p align="center">
  <img src="docs/assets/readme/gallery/01-status-1password.png" width="32%" alt="1Password status page overview">
  <img src="docs/assets/readme/gallery/02-status-1password-hover.png" width="32%" alt="1Password status page hover details">
  <img src="docs/assets/readme/gallery/03-status-claude.png" width="32%" alt="Claude status page overview">
</p>

<p align="center">
  <img src="docs/assets/readme/gallery/04-benchmark-ranking.png" width="32%" alt="AI Stupid Level benchmark ranking overview">
  <img src="docs/assets/readme/gallery/05-benchmark-panels.png" width="32%" alt="AI Stupid Level vendor comparison and recommendations panels">
  <img src="docs/assets/readme/gallery/06-benchmark-hover.png" width="32%" alt="AI Stupid Level hover card details">
</p>

## Download

- Latest builds are published on [GitHub Releases](https://github.com/Snowyyyyyy1/MenuStatus/releases/latest)
- Requires **macOS 14.0+**
- The repository includes a GitHub Actions workflow that builds a Release `.app`, packages it as a `.dmg`, and uploads it to Releases
- Signed release builds can check GitHub Pages for `appcast.xml` and install updates in-app via Sparkle

If Apple signing and notarization secrets are not configured yet, the workflow can still publish an unsigned `.dmg` so the release path remains testable end to end.

## Compatibility

### Supported

- Atlassian Statuspage pages
- incident.io pages
- built-in OpenAI and Anthropic providers
- compatible custom URLs using those same two page formats

### Not Supported

- arbitrary custom status websites outside those formats
- providers with fully custom status UIs that do not expose compatible Atlassian Statuspage or incident.io structures

## Privacy

MenuStatus reads public HTTPS status endpoints and public AI benchmark data. No API keys, no accounts, and no telemetry are required for the core experience.

## Build From Source

### Requirements

- macOS 14.0+
- Xcode 15+ command line tools
- [Tuist](https://tuist.io)

### Run Locally

```bash
./run-menubar.sh
```

To stop:

```bash
./stop-menubar.sh
```

### Development

```bash
# Generate Xcode project
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open

# Build
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme MenuStatus -configuration Debug -derivedDataPath .build

# Test
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme MenuStatus -configuration Debug -derivedDataPath .build
```

### Publish A DMG Release

Push a version tag and GitHub Actions will build a Release `.app`, package it as a `.dmg`, upload it to GitHub Releases, and publish `appcast.xml` to GitHub Pages:

```bash
git tag v0.1.0
git push origin v0.1.0
```

The workflow is defined in `.github/workflows/release.yml` and uses [`package-app.sh`](./package-app.sh).

By default the script uses `hdiutil` so it works reliably in CI. If you want a styled Finder layout locally and already have [`create-dmg`](https://github.com/create-dmg/create-dmg) installed, run `USE_CREATE_DMG=1 ./package-app.sh 0.1.0`.

One-time Sparkle setup:

```bash
./Scripts/setup-sparkle-keys.sh
```

Required GitHub repository secrets for DMG-only in-app updates:

- `SPARKLE_PUBLIC_ED_KEY`: Public Ed25519 key embedded in release builds
- `SPARKLE_PRIVATE_ED_KEY`: Private Ed25519 key used in CI to sign the DMG and generate `appcast.xml`

GitHub Pages must be enabled for this repository. The workflow publishes the update feed to:

```text
https://<owner>.github.io/<repo>/appcast.xml
```

The release build injects these values during `tuist generate`:

- `MENU_STATUS_VERSION`
- `MENU_STATUS_BUILD`
- `MENU_STATUS_FEED_URL`
- `MENU_STATUS_PUBLIC_ED_KEY`

Recommended GitHub repository secrets for signed/notarized builds:

- `APPLE_CERTIFICATE_P12_BASE64`: Base64-encoded Developer ID Application certificate (`.p12`)
- `APPLE_CERTIFICATE_PASSWORD`: Password for the `.p12`
- `APPLE_SIGNING_IDENTITY`: Signing identity, for example `Developer ID Application: Your Name (TEAMID)`
- `APPLE_ID`: Apple ID email used for notarization
- `APPLE_APP_SPECIFIC_PASSWORD`: App-specific password for that Apple ID
- `APPLE_TEAM_ID`: Apple Developer team ID

If the Apple signing secrets are omitted, the workflow still publishes a DMG and appcast, but signed/notarized releases are the intended production setup.

## Architecture

```text
ProviderConfigStore ──providers──► StatusStore ──@Observable──► SwiftUI Views
                                       │
StatusClient ──fetch & parse───────────┘
                                       │
                                  SettingsStore
                                  (UserDefaults)

AIStupidLevelClient ──fetch──────────► AIStupidLevelStore ──@Observable──► AIStupidLevelPageView
```

| Layer | Responsibility |
|-------|----------------|
| **Status Models** (`StatusModels.swift`) | Provider configs, incidents, component uptime, presentation types |
| **Provider Config** (`ProviderConfigStore.swift`) | Runtime provider list, persistence, auto-detection |
| **Status Client** (`StatusClient.swift`) | Network requests and HTML parsing for Atlassian Statuspage and incident.io |
| **Status Store** (`StatusStore.swift`) | Observable state, polling, history derivation, grouped sections |
| **AI Stupid Level Client** (`AIStupidLevelClient.swift`) | Benchmark, alerts, recommendations, degradations, and model-detail fetches |
| **AI Stupid Level Store** (`AIStupidLevelStore.swift`) | Observable benchmark state, caching, polling, and hover prefetching |
| **Views** | MenuBarExtra, provider tabs, uptime rows, benchmark panels, settings |

Generated `.xcodeproj` / `.xcworkspace` and build outputs (`.build/`, `Derived/`) are gitignored.

## License

MIT
