# TextPolish — Developer & Agent Guide

Technical documentation for contributors and AI coding agents.

---

## Project Overview

**TextPolish** is a macOS menu bar app that fixes grammar and typos in any application using global keyboard shortcuts. It copies selected text, sends it to an AI provider for correction, pastes the result, and restores the original clipboard.

### Core Principles

1. **Fast & minimal** — No heavy UI, instant hotkeys, small footprint
2. **Clipboard safe** — Always snapshot and restore user's clipboard
3. **Minimal edits** — Fix errors only, preserve voice and formatting
4. **Fail gracefully** — Show clear errors, never lose user data

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User triggers                         │
│                    hotkey (⌃⌥⌘G / ⌃⌥⌘⇧G)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     HotKeyManager                            │
│              (Carbon global hotkey registration)             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   CorrectionController                       │
│         (orchestrates copy → correct → paste flow)           │
│                                                              │
│  1. Snapshot clipboard (PasteboardController)                │
│  2. Send ⌘C via KeyboardController                          │
│  3. Wait for clipboard change                                │
│  4. Call GrammarCorrector.correct(text)                      │
│  5. Set corrected text to clipboard                          │
│  6. Send ⌘V via KeyboardController                          │
│  7. Restore original clipboard                               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              GeminiCorrector / OpenRouterCorrector           │
│                    (AI provider API calls)                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Code Map

```
src/
├── GrammarCorrectionMain.swift   # Entry point
├── AppDelegate.swift             # Menu bar UI, settings, Sparkle updates
├── CorrectionController.swift    # Copy→correct→paste orchestration
├── HotKeyManager.swift           # Carbon global hotkey registration
├── KeyboardController.swift      # CGEvent keyboard simulation (⌘A/⌘C/⌘V)
├── PasteboardController.swift    # Clipboard snapshot/restore/wait
├── GrammarCorrector.swift        # Protocol for correction providers
├── GeminiCorrector.swift         # Google Gemini API implementation
├── OpenRouterCorrector.swift     # OpenRouter API implementation
├── CorrectorFactory.swift        # Provider selection factory
├── Settings.swift                # JSON settings persistence
├── Keychain.swift                # macOS Keychain wrapper
├── FeedbackPresenter.swift       # Status item visual feedback
├── UpdateStatus.swift            # Update state enum
└── UpdateCheckFeedback.swift     # Sparkle update feedback

scripts/
├── build_app.sh                  # Build TextPolish.app bundle
├── build_pkg.sh                  # Build .pkg installer
├── sign_and_notarize.sh          # Code signing & notarization
├── sparkle_generate_keys.sh      # Generate Sparkle EdDSA keys
├── sparkle_generate_appcast.sh   # Generate appcast.xml
└── cleanup_all.sh                # Clean build artifacts & user data

Tests/GrammarCorrectionTests/
├── CorrectionControllerTests.swift
├── HotKeyManagerTests.swift
├── SettingsHotKeyTests.swift
└── ...
```

---

## Build & Run

### Quick start

```bash
./scripts/build_app.sh
open ./build/TextPolish.app
```

### SwiftPM (development)

```bash
swift build
swift run TextPolish

# Release build
swift build -c release
swift run -c release TextPolish
```

### Run tests

```bash
swift test
```

### Build installer

```bash
./scripts/build_pkg.sh
open ./build/TextPolish.pkg
```

---

## Settings

Settings file: `~/Library/Application Support/TextPolish/settings.json`

### Key fields

| Field | Default | Description |
|-------|---------|-------------|
| `provider` | `"gemini"` | `"gemini"` or `"openRouter"` |
| `geminiModel` | `"gemini-2.0-flash-lite-001"` | Gemini model name |
| `openRouterModel` | `"meta-llama/llama-3.2-3b-instruct:free"` | OpenRouter model ID |
| `correctionLanguage` | `"auto"` | `"auto"`, `"en-US"`, or `"id-ID"` |
| `requestTimeoutSeconds` | `20` | API request timeout |
| `fallbackToOpenRouterOnGeminiError` | `false` | Retry with OpenRouter on Gemini 429/5xx |

### Timing profiles

Per-app timing overrides (keys are bundle IDs or app names):

```json
{
  "timingProfiles": {
    "Discord": {
      "copyTimeoutMilliseconds": 1200,
      "pasteSettleDelayMilliseconds": 40
    }
  }
}
```

### API keys

Priority order for API key resolution:
1. macOS Keychain (service: `com.kxxil01.TextPolish`)
2. Legacy Keychain (service: `com.ilham.GrammarCorrection`)
3. Settings file (`geminiApiKey` / `openRouterApiKey`)
4. Environment variables (`GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY`)

---

## Key Behaviors

### Clipboard safety

```swift
let snapshot = pasteboard.snapshot()
defer { pasteboard.restore(snapshot) }
// ... correction logic ...
```

Always restore clipboard, even on error or cancellation.

### Copy detection

Uses a sentinel value to detect when clipboard actually changes:

```swift
pasteboard.setString("GC_COPY_SENTINEL_...")
keyboard.sendCommandC()
// Wait for clipboard to change from sentinel
```

### Correction validation

- Compares Levenshtein similarity between original and corrected text
- Rejects if similarity < `minSimilarity` (default 0.65)
- Retries up to `maxAttempts` if LLM over-rewrites

### Protected content

Regex-protects content that should not be modified:
- Code blocks (``` ... ```)
- Inline code (`...`)
- URLs
- Discord tokens (`<@id>`, `<#channel>`, `<:emoji:id>`)

---

## Coding Conventions

- **Swift concurrency**: Use `async/await`, mark UI code `@MainActor`
- **Error handling**: Show user-friendly errors via `FeedbackPresenter`
- **Dependencies**: Apple frameworks only (no external SwiftPM deps in main target)
- **File size**: Keep files small and single-purpose
- **Logging**: Use `NSLog("[TextPolish] ...")` for debugging

---

## Release Process

1. Update version in `scripts/build_app.sh`
2. Create GitHub release tag (e.g., `v1.0.0`)
3. CI builds app, signs, generates appcast, uploads assets

### Signing (optional but recommended)

```bash
export CODESIGN_IDENTITY="Developer ID Application: ..."
export NOTARY_PROFILE="TextPolishNotary"
./scripts/sign_and_notarize.sh
```

---

## Roadmap

### Reliability
- [ ] Debounce rapid hotkey presses
- [ ] Esc-to-cancel during correction
- [ ] Diagnostics panel (last error, provider status)

### Features
- [ ] Undo last correction (hotkey)
- [ ] Correction history log
- [ ] Custom prompts/modes (formal, casual, shorten)
- [ ] More providers (Claude, OpenAI, Ollama)

### Distribution
- [ ] Proper app icon
- [ ] Xcode project for easier distribution

---

## Troubleshooting (Development)

**Accessibility not working?**
- Check System Settings → Privacy & Security → Accessibility
- The app must be in /Applications for reliable permissions

**Hotkeys not registering?**
- Check for conflicts with other apps
- Verify Carbon event handler is installed

**Clipboard not updating?**
- Some apps have delayed clipboard updates
- Adjust `copyTimeoutMilliseconds` in timing profiles

**Keychain prompts?**
- First-time access requires user approval
- Check Keychain Access.app for stored items
