# MenuStatus

MenuStatus is a macOS menu bar app for checking the public status of OpenAI and Anthropic at a glance. It fetches each provider's status summary plus recent component history, then renders the current health directly from the menu bar.

## Features

- Menu bar only app via `LSUIElement`
- Polls provider status every 60 seconds
- Shows overall health with a status icon in the menu bar
- Displays provider-level summaries and component timelines
- Uses official status APIs and status page history data

## Tech Stack

- SwiftUI
- Observation
- Foundation networking
- Tuist for project generation and builds
- XCTest for unit tests

## Requirements

- macOS 14.0+
- Xcode 15+ command line tooling
- Tuist installed locally

## Getting Started

Generate the project:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open
```

Build the app:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build \
  -scheme MenuStatus \
  -configuration Debug \
  -derivedDataPath .build
```

Run the menu bar app with the helper script:

```bash
./run-menubar.sh
```

Stop the running app:

```bash
./stop-menubar.sh
```

## Tests

Run unit tests:

```bash
TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild test \
  -scheme MenuStatus \
  -configuration Debug \
  -derivedDataPath .build
```

Validate helper script syntax after editing scripts:

```bash
bash -n run-menubar.sh
bash -n stop-menubar.sh
```

## Project Structure

```text
.
├── Project.swift
├── Tuist.swift
├── Sources/
│   ├── MenuStatusApp.swift
│   ├── StatusClient.swift
│   ├── StatusModels.swift
│   ├── StatusMenuContentView.swift
│   ├── StatusRowViews.swift
│   └── StatusStore.swift
├── Tests/
│   ├── StatusClientTests.swift
│   └── StatusStoreTests.swift
├── run-menubar.sh
└── stop-menubar.sh
```

## Notes

- Build outputs in `.build/`, `Derived/`, and generated Xcode files should not be edited by hand.
- Local agent/editor metadata such as `AGENTS.md`, `.agent/`, `.agents/`, `.codex/`, and similar folders are intended to stay untracked.
- The app only reads public HTTPS status endpoints and does not require secrets.
