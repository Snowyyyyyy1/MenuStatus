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

### Current Fix Direction

- Keep the CodexBar-style SwiftUI content width state.
- Keep a tiny `NSViewRepresentable` accessor only to reach the hosting `NSWindow`.
- Do not manually compute the full window frame.
- Use `NSWindow.setContentSize(...)` so AppKit keeps responsibility for titlebar/toolbar frame calculation.

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
