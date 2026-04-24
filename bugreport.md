# MenuStatus Bug Report Log

## 2026-04-24 - Settings Providers width/toolbar clipping loop

### Symptoms

- Debug/local Settings Providers pane alternated between two regressions:
  - Window width did not expand from the General pane width to the Providers pane width.
  - After forcing width expansion, the Providers content was clipped under the native Settings toolbar/title area.
- Screenshot evidence: Providers toolbar is selected, window is wide, but the first provider row and right-side `OpenAI` header start behind the toolbar divider.

### Reference Checked

- CodexBar `PreferencesView.swift` uses:
  - `@State contentWidth/contentHeight`
  - pane-specific preferred widths
  - `.frame(width: contentWidth, height: contentHeight)`
  - `Settings { ... }.windowResizability(.contentSize)`
- CodexBar does not manually compute or set the full `NSWindow` frame for Settings pane switches.

### Root Cause

- MenuStatus needed explicit window sizing because the pure CodexBar-style SwiftUI content width update did not reliably resize its Settings window.
- The first explicit fix used `NSWindow.setFrame(...)` with a manually computed frame.
- That restored width changes but crossed the Settings scene's AppKit boundary: the native toolbar/titlebar safe area was no longer reliably owned by SwiftUI/AppKit, so Providers content could start under the toolbar.
- The app is being built on macOS 26.4.1 with Xcode 26.4.1 (`DTSDKName = macosx26.4`, Mach-O `sdk 26.4`). The glassy macOS 26 Settings toolbar/material changes are a likely trigger for the altered toolbar/content layout metrics, but not the whole cause: installed CodexBar builds checked locally are also linked against SDK 26.4 and do not require manual Settings window resizing.
- Apple documents `Settings` as content-size-resizable by default and defines `.contentSize` in terms of the content's min/max size. That is a constraint strategy, not a guarantee that every later `TabView` intrinsic-width change will resize an already-visible Settings window.
- Apple also distinguishes the whole content view from `contentLayoutRect`, the non-obscured area below a full-size titlebar/toolbar. Any fix that manually changes full frame or content height risks re-entering the toolbar overlap class of bugs on macOS 26-style Settings windows.

### Current Fix Direction

- Keep the CodexBar-style SwiftUI content width state.
- Keep a tiny `NSViewRepresentable` accessor only to reach the hosting `NSWindow`.
- Do not manually compute the full window frame.
- Treat SwiftUI as the owner of the Settings content height and native toolbar safe area.
- The AppKit bridge is width-only: change the content width when SwiftUI's content-size strategy misses the pane switch, and preserve the current content height.
- `v0.1.13-beta.6` still used `setContentSize(width + height)` and could reproduce the toolbar clipping. The next fix changes the resize helper to preserve the current content height and only replace width.

### Regression Guard

- `MenuChromeTests` covers the pane content-size contract and meaningful resize detection.
- Manual verification must include both:
  - General -> Providers width expands.
  - Providers top content is not hidden under the toolbar.

### Verification Notes

- After switching to `NSWindow.setContentSize(...)`, AppleScript accessibility verification showed:
  - General window size: `496 x 668`
  - Providers window size: `720 x 668`
  - Providers toolbar bottom: `329`
  - First provider row title top: `351`
  - Provider detail header top: `357`
- The content starts below the toolbar again while width expansion/shrink still works.
- After switching to width-only content resizing, AppleScript accessibility verification showed:
  - General window size: `496 x 668`
  - Providers window size: `720 x 668`
  - Providers toolbar bottom: `200`
  - First provider row title top: `222`
  - Provider detail header top: `228`
  - Closing and reopening Settings while still on Providers kept the same non-overlapping coordinates.
- After tightening the helper API to `targetContentWidth` / `needsWidthResize`, verification again showed:
  - General window size after shrink: `496 x 668`
  - Providers window size after re-expand: `720 x 668`
  - Providers toolbar bottom: `200`
  - Provider list `OpenAI` top: `222`
  - Provider detail `OpenAI` top: `228`
  - `tuist xcodebuild test -scheme MenuStatus -configuration Debug -derivedDataPath .build`: 125 tests passed.
- Final implementation removes the old `targetContentSize` / `needsResize` helper names entirely. `SettingsWindowContentSizing` now exposes only width-oriented resize helpers.
- Final Debug verification:
  - General -> Providers -> General -> Providers: `496 x 668` -> `720 x 668` -> `496 x 668` -> `720 x 668`
  - Providers toolbar bottom: `234`
  - Provider list `OpenAI` top: `256`
  - Provider detail `OpenAI` top: `262`
- Final Release verification:
  - General -> Providers -> General -> Providers: `496 x 668` -> `720 x 668` -> `496 x 668` -> `720 x 668`
  - Providers toolbar bottom: `234`
  - Provider list `OpenAI` top: `256`
  - Provider detail `OpenAI` top: `262`
  - Release app remained running after verification with 7 menu bar items visible to accessibility.
