# TextPolish — Agent Notes

Scope: entire repo.

## Product Goal

Build a **small, fast, reliable** macOS menu-bar app that can fix grammar/typos in **Discord (and any app)** via **global shortcuts**:

- Correct selection: `⌃⌥⌘G`
- Correct whole input: `⌃⌥⌘⇧G` (does `⌘A` first)

Core behavior: **copy → correct → paste**, while **restoring the user’s clipboard**.

## MVP Definition

Must-haves:

- Menu-bar only (`LSUIElement`), launches quickly, minimal UI.
- Two global hotkeys (selection + whole input).
- Works in Discord’s message box reliably (requires focus/selection as appropriate).
- Preserves clipboard even on error/timeouts.
- Retains original formatting (line breaks/Markdown) and makes minimal edits (no “AI rewrite” tone changes).
- Uses a configurable backend:
  - Default: Gemini (`provider: "gemini"`)
  - Optional: OpenRouter (`provider: "openRouter"`)
- Backend is selectable in-app from the status bar menu.
- API keys are entered in-app and stored in Keychain (no manual config edits required for secrets).
- Gemini model can be changed in-app if the default model returns 404.
- Gemini model can be auto-detected in-app (lists available models for the API key).
- Clear setup instructions (Accessibility permission) and basic settings docs.

Nice-to-haves (still MVP-friendly):

- Basic feedback via status bar icon/tooltip (success/info/error).
- Configurable backend + model + timeouts via JSON file.
- Start at Login toggle in the status bar menu.

Non-goals for MVP:

- Injecting a custom right-click item into Discord’s context menu (requires Discord modification).
- Heavy UI/settings windows.
- Multi-platform packaging (Windows/Linux).

## What’s Implemented (Current State)

Menu bar app (no Dock icon) with hotkeys and menu items:

- `src/AppDelegate.swift`: status item + menu + hotkey hookup.
- Start at Login toggle (uses `ServiceManagement` / `SMAppService.mainApp`).
- Menu items: backend select, key/model prompts, Privacy, About, Accessibility shortcut, reveal in Finder.
- `src/HotKeyManager.swift`: Carbon global hotkeys.
- `src/CorrectionController.swift`: orchestrates copy/correct/paste with safety guards.
- `src/KeyboardController.swift`: sends `⌘A/⌘C/⌘V` via CGEvent (needs Accessibility).
- `src/PasteboardController.swift`: snapshots/restores clipboard; waits for copied text.
- `src/GeminiCorrector.swift`: Gemini backend (fast LLM grammar correction).
- `src/OpenRouterCorrector.swift`: OpenRouter backend (OpenAI-compatible chat completions).
- `src/CorrectorFactory.swift`: selects provider; fails cleanly if misconfigured.
- `src/Settings.swift`: `~/Library/Application Support/TextPolish/settings.json` (auto-created; migrates from legacy `GrammarCorrection` folder if present).
- `scripts/build_app.sh`: builds `build/TextPolish.app` via `swiftc`.
- `scripts/build_pkg.sh`: builds `build/TextPolish.pkg` installer (installs into `/Applications`, non-relocatable).
- `scripts/pkg_scripts/postinstall`: launches the app after `.pkg` install (so new users see the menu bar icon immediately).
- `scripts/cleanup_all.sh`: removes app + settings + Keychain items (best-effort) and cleans repo build artifacts.
- `scripts/sign_and_notarize.sh`: optional paid distribution path (Developer ID) for Gatekeeper trust.
- Bundle identifier: `com.kxxil01.TextPolish` (reads/migrates legacy Keychain items from `com.ilham.GrammarCorrection`).
- API key prompt supports paste via both `⌘V` and `⌃V`.

## Build & Run

```bash
./scripts/build_app.sh
open ./build/TextPolish.app
```

SwiftPM (dev):

```bash
swift build -c release
swift run -c release TextPolish
```

Grant permissions:

- System Settings → Privacy & Security → Accessibility → enable `TextPolish`

## Settings (Backend Selection)

Settings file:

- `~/Library/Application Support/TextPolish/settings.json`
  - Migrates from legacy `~/Library/Application Support/GrammarCorrection/settings.json` if present

Common fields:

- `provider`: `"gemini"` (default) or `"openRouter"`
- `requestTimeoutSeconds`: e.g. `20`

Gemini fields:

- `geminiApiKey`: legacy fallback (prefer Keychain); or set env `GEMINI_API_KEY` / `GOOGLE_API_KEY`
- `geminiModel`: default `"gemini-2.0-flash-lite-001"`
- `geminiBaseURL`: default `"https://generativelanguage.googleapis.com"`

OpenRouter fields:

- `openRouterApiKey`: legacy fallback (prefer Keychain); or set env `OPENROUTER_API_KEY`
- `openRouterModel`: default `"meta-llama/llama-3.2-3b-instruct:free"` (free model)
- `openRouterBaseURL`: default `"https://openrouter.ai/api/v1"`

## Reliability Principles (Must Keep)

- Never lose user clipboard: snapshot → restore via `defer`.
- Never block the main thread: network operations are `async`.
- Avoid concurrency hazards: keep UI/feedback `@MainActor`.
- Avoid feature creep: no heavy dependencies, no big UI.
- Fail safely: if copy/correct fails, show error and restore clipboard; avoid “random paste”.
- Keep hotkeys responsive: minimal work before copy; short sleeps only as needed.
- Prefer minimal edits: preserve formatting and the user’s voice; avoid rephrasing unless required for correctness.

## Known Risks / Edge Cases

- If Discord (or another app) doesn’t update the clipboard on `⌘C`, we must avoid using stale clipboard content.
- “Correct all” assumes focus is in the message input; otherwise `⌘A` may select other content.
- Network backends can time out; keep sane timeouts and clear error feedback.
- LLMs can occasionally return quotes/code fences; Gemini backend trims common wrappers.

## Roadmap

### Next (Reliability + UX)

- Harden copy detection (don’t proceed if `⌘C` didn’t change clipboard).
- Add a small debounce/throttle so rapid hotkey presses don’t stack requests.
- Make hotkeys configurable (with conflict detection).
- Add a “dry run” / preview popover option (optional) without heavy UI.
- Add cancellation (Esc / menu) so you can stop an in-flight correction.
- Add local-only option: offline model (stretch).

### Packaging / Distribution

- Add proper app icon + versioning.
- Add code signing/notarization guidance (and optional scripts).
- Optional: create an Xcode project for easier distribution.

## Trust / Professional Checklist

Goal: feel safe to run even outside the App Store.

- Ship a real `.app` bundle (not `swift run`) so prompts show the app name/version.
- Use a stable `CFBundleIdentifier` (`com.kxxil01.TextPolish`). The app can still read/migrate legacy Keychain items from `com.ilham.GrammarCorrection`.
- Store secrets only in Keychain (with clear labels like “TextPolish — Gemini API Key”).
- Be transparent: keep a short in-app Privacy note (menu item) describing what is sent to Gemini/OpenRouter and what is not stored.
- Sign + notarize releases (Developer ID) so Gatekeeper trusts the build and Keychain prompts show a developer identity.

Free alternatives (no Gatekeeper trust, but usable):

- Build locally (avoids quarantine for personal use).
- Remove quarantine for shared builds: `xattr -dr com.apple.quarantine TextPolish.app`
- (Optional) local certificate signing to improve “identity” consistency.

Release helper:

- `scripts/sign_and_notarize.sh` (expects `CODESIGN_IDENTITY` and `NOTARY_PROFILE`)

### Backend Improvements

- Allow per-provider prompt/model tuning (Gemini).
- Add streaming/cancellation (Gemini) if needed for responsiveness.
- Add provider selection in a minimal settings menu (still lightweight).

## Coding Conventions

- Swift 6; prefer `async/await` and `@MainActor` for UI code.
- Keep dependencies to Apple frameworks only (no SwiftPM deps for MVP).
- Keep files small and single-purpose.
- Prefer minimal edits; keep LLM prompt strict (“return only corrected text”).
