# TextPolish — Developer & Agent Guide

Technical documentation for contributors and AI coding agents.

---

## Project Overview

**TextPolish** is a macOS menu bar app that provides AI-powered text enhancement in any application using global keyboard shortcuts. It offers two main features:

1. **Grammar Correction** - Fixes grammar and typos by copying selected text, sending it to an AI provider, pasting the result, and restoring the original clipboard
2. **Tone Analysis** - Analyzes the tone and sentiment of selected text, providing feedback on emotional impact and suggestions

The app tracks daily usage for both features and displays the combined count in the status bar badge.

### Core Principles

1. **Fast & minimal** — No heavy UI, instant hotkeys, small footprint
2. **Clipboard safe** — Always snapshot and restore user's clipboard
3. **Minimal edits** — Fix errors only, preserve voice and formatting
4. **Fail gracefully** — Show clear errors, never lose user data

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        User triggers                        │
│                    hotkey (⌃⌥⌘G / ⌃⌥⌘⇧G)                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     HotKeyManager                           │
│              (Carbon global hotkey registration)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   CorrectionController                      │
│         (orchestrates copy → correct → paste flow)          │
│                                                             │
│  1. Snapshot clipboard (PasteboardController)               │
│  2. Send ⌘C via KeyboardController                          │
│  3. Wait for clipboard change                               │
│  4. Call GrammarCorrector.correct(text)                     │
│  5. Set corrected text to clipboard                         │
│  6. Send ⌘V via KeyboardController                          │
│  7. Restore original clipboard                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              GeminiCorrector / OpenRouterCorrector          │
│                    (AI provider API calls)                  │
└─────────────────────────────────────────────────────────────┘
```

### Tone Analysis Flow
```
┌─────────────────────────────────────────────────────────────┐
│                        User triggers                        │
│                          hotkey (TBD)                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     HotKeyManager                           │
│              (Carbon global hotkey registration)            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                ToneAnalysisController                       │
│         (orchestrates copy → analyze → show result)         │
│                                                             │
│  1. Snapshot clipboard (PasteboardController)               │
│  2. Send ⌘C via KeyboardController                          │
│  3. Wait for clipboard change                               │
│  4. Call ToneAnalyzer.analyze(text)                         │
│  5. Display result in window                                │
│  6. Restore original clipboard                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     ToneAnalyzerFactory                     │
│              (creates analyzer based on provider)           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              GeminiCorrector / OpenRouterCorrector          │
│                    (AI provider API calls)                  │
└─────────────────────────────────────────────────────────────┘
```

### Usage Tracking
```
┌─────────────────────────────────────────────────────────────┐
│                      AppDelegate                            │
│                                                             │
│  • Grammar correction counter (daily)                       │
│  • Tone analysis counter (daily)                            │
│  • Combined badge on status bar                             │
│  • Automatic reset at midnight                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Code Map

```
src/
├── GrammarCorrectionMain.swift   # Entry point
├── AppDelegate.swift             # Menu bar UI, settings, Sparkle updates, usage tracking
├── CorrectionController.swift    # Copy→correct→paste orchestration
├── ToneAnalysisController.swift  # Tone analysis orchestration
├── ToneAnalyzer.swift           # Protocol for tone analyzers
├── ToneAnalyzerFactory.swift    # Tone analyzer factory
├── ToneAnalysisResultWindow.swift # Results window UI
├── ToneAnalysisResultPresenter.swift # Result presentation logic
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
├── UpdateCheckFeedback.swift     # Sparkle update feedback
├── FallbackController.swift     # Error fallback handling
├── SettingsWindowController.swift # Settings window controller
└── SettingsWindowViewController.swift # Settings UI and logic

scripts/
├── build_app.sh                  # Build TextPolish.app bundle
├── build_pkg.sh                  # Build .pkg installer
├── sign_and_notarize.sh          # Code signing & notarization
├── sparkle_generate_keys.sh      # Generate Sparkle EdDSA keys
├── sparkle_generate_appcast.sh   # Generate appcast.xml
└── cleanup_all.sh                # Clean build artifacts & user data

Tests/GrammarCorrectionTests/
├── CorrectionControllerTests.swift    # Grammar correction tests
├── FallbackControllerTests.swift     # Fallback handling tests
├── HotKeyManagerTests.swift         # Hotkey registration tests
├── SettingsHotKeyTests.swift        # Settings and hotkey tests
├── SettingsWindowControllerTests.swift # Settings window tests
├── SettingsWindowViewControllerTests.swift # Settings UI tests
├── SettingsIntegrationTests.swift   # Integration tests
├── ModelDetectorTests.swift         # Model detection tests
├── StatusItemFeedbackTests.swift    # Status item tests
├── UpdateCheckFeedbackTests.swift   # Update feedback tests
├── UpdateStatusTests.swift          # Update status tests
├── ProviderWordingTests.swift       # Provider error message tests
├── KeyComboFieldTests.swift         # Key combo field tests
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

### Usage tracking

The app tracks daily usage for both features:

- **Grammar corrections**: Increment on successful text correction
- **Tone analyses**: Increment on successful tone analysis
- **Combined badge**: Status bar shows total (corrections + analyses)
- **Daily reset**: Counters automatically reset at midnight
- **Storage**: UserDefaults with date tracking

```swift
// Incremented on successful grammar correction
incrementCorrectionCount()

// Incremented on successful tone analysis
incrementToneAnalysisCount()

// Combined count displayed in status bar
makeIconWithBadge(count: todayCorrectionCount + todayToneAnalysisCount)
```

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

### Tone analysis

The tone analysis feature provides feedback on text emotional impact:

- **Analyzes**: Tone, sentiment, formality level
- **Shows results**: In dedicated window with detailed breakdown
- **Copies text**: Uses same clipboard safety pattern as correction
- **No paste**: Results displayed in window, not pasted to app
- **Counts usage**: Increments daily counter on successful analysis
- **Same providers**: Uses Gemini/OpenRouter for AI analysis

---

## Coding Conventions

- **Swift concurrency**: Use `async/await`, mark UI code `@MainActor`
- **Error handling**: Show user-friendly errors via `FeedbackPresenter`
- **Dependencies**: Apple frameworks only (no external SwiftPM deps in main target)
- **File size**: Keep files small and single-purpose
- **Logging**: Use `NSLog("[TextPolish] ...")` for debugging
- **Testing**: Suppress UI dialogs in test environment using `NSClassFromString("XCTestCase")`
- **Test environment**: Use `#if DEBUG` guards for test-specific behavior

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
- [x] Tone analysis (sentiment, formality, emotional impact)
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

---

## Testing

The project uses **Swift Testing** with **XCTest** for comprehensive coverage:

### Running Tests
```bash
swift test
swift test --enable-code-coverage  # With coverage
```

### Test Environment Guards

UI dialogs are suppressed in test environment to prevent CI/CD blocking:

```swift
#if DEBUG
if NSClassFromString("XCTestCase") != nil {
    NSLog("[TextPolish] Error suppressed in test environment: \(error)")
    return
}
#endif
// Show actual dialog in production
```

### Test Coverage

- **Unit tests**: Core logic and controllers
- **Integration tests**: Settings window and app integration
- **UI tests**: Window controllers and view controllers
- **Mocking**: Comprehensive mocks for providers, keyboard, pasteboard

**Current status**: 135 tests, 100% pass rate

### CI/CD Best Practices

- All popup dialogs must include test environment guards
- Use logging instead of blocking UI in tests
- Mock external dependencies (API calls, clipboard, keyboard)
- Test async/await code with proper task management
