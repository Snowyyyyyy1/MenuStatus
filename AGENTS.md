# Repository Guidelines

## Project Structure & Module Organization
`Project.swift` and `Tuist.swift` are the source of truth for targets and build settings. Keep app code in `Sources/` and follow the existing split: `*Models*.swift` for API/domain types, `*Client*.swift` for networking and decoding, `*Store*.swift` for observable state, `*Menu*View*.swift` for top-level menu UI, and `*Row*View*.swift` for row rendering. `run-menubar.sh` and `stop-menubar.sh` are the canonical local run helpers. Treat `.build/`, `Derived/`, and generated Xcode files as build artifacts, not hand-edited source.

## Build, Test, and Development Commands
Use Tuist-first commands from the repo root:

- `TUIST_SKIP_UPDATE_CHECK=1 tuist generate --no-open` regenerates the Xcode project/workspace.
- `TUIST_SKIP_UPDATE_CHECK=1 tuist xcodebuild build -scheme MenuStatus -configuration Debug -derivedDataPath .build` builds the app without opening Xcode.
- `./run-menubar.sh` stops any running instance, regenerates, builds, and launches the menu bar app.
- `./stop-menubar.sh` stops the running app instance.
- `bash -n run-menubar.sh && bash -n stop-menubar.sh` validates shell script syntax after script edits.

## Coding Style & Naming Conventions
Write simple SwiftUI and Foundation code with 4-space indentation. Keep business logic out of views; networking belongs in clients, state transitions in `StatusStore`, and `MenuStatusApp` should stay focused on scene wiring. Prefer clear type names like `StatusClient`, `StatusStore`, and `StatusMenuContentView`. Use `UpperCamelCase` for types and `lowerCamelCase` for properties and methods.

## Testing Guidelines
There is no XCTest target in this checkout yet. For now, validate changes with a clean build and manual menu bar smoke test via `./run-menubar.sh`. When adding tests, create a dedicated test target through Tuist, keep test files under a `Tests/` directory, and mirror source names such as `StatusStoreTests.swift`.

## Commit & Pull Request Guidelines
Git history is not available in this workspace, so use short imperative commit subjects, for example `Add incident timeline refresh`. Keep commits scoped to one change. PRs should include a brief summary, commands run, and screenshots or short recordings for any menu/UI change. Link the relevant issue when one exists and call out changes to `Project.swift`, scripts, or app lifecycle behavior explicitly.

## Security & Configuration Tips
This app fetches public status data over HTTPS. Do not hardcode secrets, tokens, or environment-specific credentials. If you add config files later, make sure they are ignored before committing.
