# TextPolish: Developer & Agent Guide

Technical documentation for contributors and AI coding agents.

---

## Project Overview

**TextPolish** is a macOS menu bar app that improves text in any application with a global shortcut. It sends the text to the user's AI provider (OpenAI, Gemini, Anthropic, or OpenRouter, with their own API key) and pastes the result back.

1. **Polish** (`⌃⌥⌘G`): polishes the selection, or the whole field when nothing is selected, in one of five styles: Natural (default), Minimal, Shorter, Formal, Friendly, plus an optional Custom style the user describes.
2. **Analyze Tone** (`⌃⌥⌘T`): explains how the selected text comes across, in a result window.
5. **Reply in English** (`⌃⌥⌘R`): the Polish flow with `.reply(to:)`, carrying the last explained message (`ReplyContext`, in memory for 15 minutes) as context; checked like a translation.
4. **Explain Message** (`⌃⌥⌘U`): copies the selection through `ToneAnalysisController` (a read-only selection job, like Analyze Tone), asks the provider through `MessageExplaining` (built on `TextGenerating`), and shows the meaning, tone, and phrases in `ExplainPanel`, which opens while the provider answers. The panel answers too: `ReplyIntent` quick replies (`ReplySuggestionPrompt`, placeholders instead of invented facts) or the writer's own words (`.reply(answering:)`), shown editable, then `CorrectionController.insert` pastes it into the explained app.
3. **Translate to English** (`⌃⌥⌘E`): the Polish flow with the `translateToEnglish` style; the similarity floor is off, the number, placeholder, and layout checks still apply, and Learn mode skips it.

Optional extras: a style per app, a shortcut per style, Never Change words, Preview before paste, and Learn mode with Recent Lessons.

### Core Principles

1. **Fast & minimal**: no Dock icon, instant hotkeys, small footprint
2. **Clipboard safe**: snapshot and restore the user's clipboard
3. **Keep the writer's meaning and voice**: styles change wording, never facts or requests
4. **Fail gracefully**: clear errors, never lose user data, never freeze the UI
5. **Private**: text goes only to the configured provider; logs never contain the user's text or keys

---

## Architecture

### Polish flow (`CorrectionController`)

1. Hotkey or menu action resolves the style: style shortcut, else the app's chosen style, else the built-in default for terminals and code editors (Minimal), else the default style (`Settings.polishStyle(forApp:)`).
2. Snapshot the clipboard; `SelectionProbe` (Accessibility) decides selection versus whole field (⌘A).
3. Copy with ⌘C and wait for the clipboard to change (sentinel value).
4. `GrammarCorrector.correct(_:style:)`: protect code, links, Discord tokens and Never Change terms as placeholders, build the prompt (`CorrectionPromptBuilder`), call the provider, validate, retry with the specific failed check, restore placeholders.
5. If Preview is on, `PolishReviewPanel` shows the diff (`WordDiff`, or the plain text for a translation) and waits for Paste, Cancel, or another try (Try Again, or another style), which polishes the original again while the panel stays up.
6. Paste with ⌘V (re-activating the target app if needed), restore the clipboard, show feedback.
7. If Learn is on, ask the provider to explain the main changes (`ChangeExplaining`), show `LearnPanel`, save to `LessonHistory`, which also counts each explained change (`RepeatedMistake`) so Recent Lessons can list repeated ones under Watch Out For.

### Services (`ServicesProvider`)

Right-click > Services > "Polish with TextPolish", "Translate to English with TextPolish", and "Explain with TextPolish" are declared under `NSServices` in the Info.plist that `scripts/build_app.sh` writes. macOS hands over the selected text, so Polish skips the copy step (`polish(style:text:)`) and pastes over the selection as usual.

### Command line (`CommandLinePolish`)

`TextPolish polish [--style name] [text]` and `TextPolish translate [text]` run before the menu bar app starts (see `GrammarCorrectionMain`). Text comes from the arguments or stdin, and the result goes to stdout: exit 0 on success, 1 on a provider error, 2 on a usage error. Any other arguments start the app as usual. The correction runs off the main thread while the main thread waits, so keychain reads stay off the main thread.

### Tone flow (`ToneAnalysisController`)

Copy as above, then `ToneAnalyzer.analyze(_:)` (from `ToneAnalyzerFactory`, with provider fallback), then show `ToneAnalysisResultWindow` and restore the clipboard.

---

## Code Map

```
src/
├── GrammarCorrectionMain.swift, AppDelegate.swift, AppDelegateSupport.swift
│                                   Entry point; menu, hotkey routing, settings, Sparkle, Learn and lessons wiring
├── CorrectionController.swift      Polish orchestration (copy, correct, preview, paste, restore)
├── SelectionProbe.swift            Accessibility check: selected text, nothing selected, or unknown
├── KeyboardController.swift, PasteboardController.swift
│                                   ⌘A/⌘C/⌘V events; clipboard snapshot, restore, wait
├── HotKeyManager.swift             Carbon hotkeys: Polish, Analyze Tone, Translate, optional style shortcuts
├── ServicesProvider.swift          Right-click > Services entries
├── GrammarCorrector.swift          CorrectionStyle and the corrector protocol
├── CorrectorFactory.swift          Builds the corrector for the selected provider
├── OpenAICorrector.swift, GeminiCorrector.swift, AnthropicCorrector.swift, OpenRouterCorrector.swift
├── OpenAICompatibleEndpoint.swift, Settings+CustomProvider.swift
│                                   The Custom provider: any OpenAI-compatible API through the OpenAI client
├── OpenAITokenPolicy.swift, GeminiRequestPolicy.swift, AnthropicRequestPolicy.swift
│                                   Per-model request parameters (reasoning, thinking, temperature, JSON mode)
├── CorrectionPromptBuilder.swift   Prompt rules and examples per style; retry instructions per failed check
├── TextProcessor.swift             Placeholders, cleanup, line-structure and similarity checks
├── PromptGuardrails.swift          Input limits, refusal detection, output length
├── ChangeExplanation.swift         Learn mode prompt and parser
├── WordDiff.swift                  Word-level diff for the preview
├── PolishReviewPanel.swift         Preview panel (non-activating)
├── LearnPanel.swift, LessonHistory.swift, LessonsWindow.swift
├── ToneAnalysisController.swift, ToneAnalyzer.swift, ToneAnalyzerFactory.swift, *ToneAnalyzer.swift
├── Settings.swift                  JSON settings, defaults, normalization, per-app styles
├── SettingsWindowController.swift, SettingsWindowViewController.swift, SettingsUIComponents.swift
├── KeyComboField.swift, PastableSecureTextField.swift
├── Keychain.swift, ProviderCredentials.swift
│                                   Secrets: existence checks never read the secret; reads happen off the main thread
├── ModelDetector.swift             Detect Model (prefers gpt-4.1-mini for OpenAI)
├── Diagnostics.swift, DiagnosticsWindow.swift, RecentLogs.swift
├── TokenUsage.swift, ModelPricing.swift, UsageLedger.swift
│                                   Usage This Month in Diagnostics: tokens from each response, list prices, usage.json
├── TPLogger.swift                  Public system log lines (subsystem com.kxxil01.TextPolish)
├── FeedbackPresenter.swift, FallbackController.swift, UpdateStatus.swift, UpdateCheckFeedback.swift
└── RetrySupport.swift, APIEndpointPaths.swift, PromptPair.swift, ControllerProtocols.swift, NotificationExtensions.swift

scripts/
├── build_app.sh, build_pkg.sh      Build the app bundle and installer
├── release.sh                      Publish a release once main CI passes (see Release Process)
├── sign_and_notarize.sh, sparkle_generate_keys.sh, sparkle_generate_appcast.sh
└── generate_app_icon.sh, cleanup_all.sh
```

---

## Build & Run

```bash
./scripts/build_app.sh && open ./build/TextPolish.app   # app bundle
swift build && swift run TextPolish                     # development
```

A local build is signed differently from releases, so macOS asks again for keychain access to saved keys.

---

## Testing

```bash
swift test                       # unit and UI-level tests
swiftlint lint --strict          # CI fails on any warning
```

- Providers are mocked with `URLProtocol` stubs; keyboard, clipboard and feedback have stubs in `CorrectionControllerTests`.
- Wait on conditions or events, never on a sleep racing another sleep. Drive stubs by call order (see `StubPasteboard.externalChangeAfterReads`).
- Tests never read real keychain secrets. Settings are isolated to a per-process temp folder.
- `TPLogger` writes to stderr during tests, so test runs stay out of the app's system log.

### Live prompt checks

Before shipping a prompt or model change, run the Polish prompts against a real provider. They are skipped unless `TEXTPOLISH_LIVE_CHECKS=1`, so CI never calls a provider. A run costs a few cents.

```bash
TEXTPOLISH_LIVE_CHECKS=1 OPENAI_API_KEY=sk-... swift test --filter LivePromptChecks
# Other providers: TEXTPOLISH_LIVE_PROVIDER=gemini|anthropic|openrouter with that provider's key variable,
# or custom with TEXTPOLISH_LIVE_BASE_URL, TEXTPOLISH_LIVE_MODEL, and an optional TEXTPOLISH_CUSTOM_API_KEY.
# Another model: TEXTPOLISH_LIVE_MODEL=gpt-5-nano
```

Model output varies between runs; each check prints its input and output so a failure can be read.

---

## Settings

File: `~/Library/Application Support/TextPolish/settings.json` (lessons are saved next to it in `lessons.json`, and monthly usage in `usage.json`).

| Field | Default | Description |
|-------|---------|-------------|
| `provider` | `gemini` | `gemini`, `openRouter`, `openAI`, `anthropic`, or `custom` |
| `customProvider` | empty | Any OpenAI-compatible API: `baseURL`, `model`, optional `apiKey`, `maxAttempts`, `minSimilarity`, `extraInstruction` |
| `openAIModel` | `gpt-4.1-mini` | Fast, no reasoning step, rewords well |
| `geminiModel` | `gemini-2.5-flash` | |
| `anthropicModel` | `claude-haiku-4-5` | |
| `openRouterModel` | `google/gemma-3n-e4b-it:free` | |
| `polishStyle` | `natural` | `natural`, `minimal`, `shorter`, `formal`, `friendly`, `custom` |
| `customStyleName` | `Custom` | The Custom style's name in menus, up to 30 characters |
| `customStyleInstruction` | none | How the Custom style sounds, up to 500 characters; Custom is hidden until it is set |
| `appPolishStyles` | `{}` | Style per app, keyed by bundle ID |
| `styleHotKeys` | `{}` | Optional shortcut per style, keyed by style |
| `hotKeyTranslate` | `⌃⌥⌘E` | Translate to English |
| `hotKeyExplain` | `⌃⌥⌘U` | Explain Message |
| `hotKeyReply` | `⌃⌥⌘R` | Reply in English |
| `explanationLanguage` | `indonesian` | `indonesian` or `simpleEnglish`, the language Explain Message writes in |
| `protectedTerms` | `[]` | Never Change words |
| `previewBeforePaste` | `false` | Confirm before pasting |
| `learnMode` | `false` | Explain the main changes after each Polish |
| `correctionLanguage` | `auto` | `auto`, `en-US`, or `id-ID` |
| `requestTimeoutSeconds` | `20` | 1 to 120 |
| `fallbackToOpenRouterOnGeminiError` | `false` | Try the paired provider when the first fails (Gemini and OpenRouter, OpenAI and Anthropic) |

Per-provider tuning: `<provider>MaxAttempts` (default 2), `<provider>MinSimilarity` (default 0.65), `<provider>ExtraInstruction`.

### Timing profiles

Per-app timing overrides (keys are bundle IDs or app names):

```json
{
  "timingProfiles": {
    "Discord": { "copyTimeoutMilliseconds": 1200, "pasteSettleDelayMilliseconds": 40 }
  }
}
```

### API keys

Resolution order: macOS Keychain (service `com.kxxil01.TextPolish`, then legacy `com.ilham.GrammarCorrection`), the settings file, then environment variables (`OPENAI_API_KEY`, `GEMINI_API_KEY` or `GOOGLE_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, `TEXTPOLISH_CUSTOM_API_KEY`).

The Custom provider reuses the OpenAI client through `OpenAICompatibleEndpoint`: its own base URL, model, and keychain account (`customApiKey`). With no key, requests go without an Authorization header. It has no fallback partner.

---

## Key Behaviors

### Clipboard safety

The original clipboard is snapshotted before copying and restored afterwards, including on error, cancel, or a canceled preview. If another app writes to the clipboard during Polish, TextPolish neither pastes nor restores.

### Validation and retries

When every attempt is rejected for a reason a person can judge (`numbersChanged`, `overRewrite`, `lineStructureChanged`), providers keep the last result (`RejectionReporting`) and `CorrectionController` shows it in the preview with a warning, even with Preview off; Return no longer pastes there. A refusal, a long answer, or a dropped placeholder is never offered.

A candidate is rejected when it is a refusal, much longer than the input, drops a placeholder, changes line structure (Minimal keeps every line; other styles may join lines inside a paragraph but must keep blank lines and list items, and add no lines; Custom may change the layout), changes a number (digits inside a word, such as the typo "everytgh8ng", are not numbers; rewrite styles may spell out 0 to 10 as a word, such as "1 more week" as "one more week"; the retry names the numbers to keep), or falls below the similarity floor (configured value for Minimal, at most 0.4 for Natural, 0.3 for Shorter, Formal, Friendly and Custom). The retry prompt names the check that failed. After `maxAttempts`, the paired provider may be tried if fallback is on.

### Keychain and the main thread

A keychain read can show a system prompt that blocks the calling thread until the user answers, and the prompt takes keyboard focus. So:
- Existence checks use attribute-only queries (`Keychain.hasConfiguredPassword`, `ProviderCredentials.isConfigured`), which never prompt.
- Secrets are read off the main thread (`Keychain.loadConfiguredPassword`, or inside a provider request). `Keychain.getConfiguredPassword` asserts it is not on the main thread.

### Logging

`TPLogger.log` writes public lines to the unified log (NSLog text is stored as `<private>`). Never log the user's text or a secret; log counts, styles, model names and outcomes. Read them with:

```bash
log show --last 10m --predicate 'subsystem == "com.kxxil01.TextPolish"'
```

Users can send the same lines from Diagnostics > Copy Logs.

---

## Coding Conventions

- Swift 5.9 package, macOS 13+, AppKit with frame-based layout; UI on `@MainActor`, async/await elsewhere
- Apple frameworks only in the app target (Sparkle is the one dependency, for updates)
- Keep files small and single-purpose; match the surrounding style
- Every user-visible change gets tests; render new windows in a temporary test to check layout, then delete it
- No em or en dashes in code, comments, docs, commits, or PRs

---

## Release Process

1. Merge the PRs to `main` (squash). CI must pass on the PR.
2. Write release notes to a file, then run:
   ```bash
   scripts/release.sh 0.0.74 notes.md
   ```
   The script waits for CI on the exact `main` commit and refuses to release if it failed, creates the release (tags have no `v` prefix), waits for the signed build (`release.yml`), and confirms the Sparkle appcast and the Homebrew cask (`kxxil01/homebrew-tap`) show the new version.
3. Users update through Sparkle (Check for Updates) or `brew upgrade --cask textpolish`.

Releases are signed with the stable "TextPolish Local" certificate, so the keychain keeps trusting new versions.

---

## Troubleshooting (Development)

- **Polish does nothing**: read the log lines above. "No changes" means the model returned the text unchanged; rejected attempts name the failed check.
- **Accessibility not working**: System Settings > Privacy & Security > Accessibility; the app should run from /Applications.
- **Hotkeys not registering**: another app may own the combination; the menu shows which shortcuts failed.
- **Clipboard not updating**: some apps copy slowly; raise `copyTimeoutMilliseconds` in a timing profile.
- **Keychain prompts**: expected for local builds; a release build asks at most once per key.
