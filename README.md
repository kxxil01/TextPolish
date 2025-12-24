# TextPolish

Small, fast menu bar app for macOS that fixes grammar and typos in any app (Discord, etc). It keeps your formatting and tone and restores your clipboard.

[![CI](https://github.com/kxxil01/TextPolish/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/kxxil01/TextPolish/actions/workflows/ci.yml)
[![Release](https://github.com/kxxil01/TextPolish/actions/workflows/release.yml/badge.svg?event=release)](https://github.com/kxxil01/TextPolish/actions/workflows/release.yml)

## Why TextPolish

Discord and other apps do not have fast, reliable grammar correction everywhere. I wanted a small menu bar app that works in any text box, runs on hotkeys, and preserves your voice.

Key goals:
- Fast, minimal UI and instant hotkeys
- Smallest possible edits, no AI rewrite tone
- Clipboard safe and reliable across apps

## Download

**Homebrew (recommended):**

```bash
brew install --cask kxxil01/tap/textpolish
```

**Manual download:**

Latest release: https://github.com/kxxil01/TextPolish/releases

- TextPolish.app.zip — drag and drop to /Applications
- TextPolish.pkg — guided installer

**Landing page:** https://textpolish.pages.dev

## Quick Start

1. Install TextPolish.app to /Applications and open it.
2. Grant Accessibility permission: System Settings -> Privacy & Security -> Accessibility -> TextPolish.
3. Set your API key from the menu: Provider -> Set Gemini API Key... (or OpenRouter).
4. Optional: Preferences -> Language to force English (US) or Indonesian.
5. Use the shortcuts below.

## Shortcuts

- Correct Selection: Ctrl+Option+Command+G
- Correct All: Ctrl+Option+Command+Shift+G (presses Command+A first)

## How it works

- Copies your selected text or current input.
- Sends that text to the chosen provider for correction.
- Pastes the corrected text back.
- Restores your clipboard.

## Architecture

Text correction flow:

```
Select text -> Copy (Cmd+C) -> Provider (Gemini/OpenRouter) -> Paste (Cmd+V) -> Restore clipboard
```

Update flow:

```
GitHub Release -> appcast.xml -> Sparkle -> TextPolish
```

## Menu

- Correct Selection / Correct All
- Cancel Correction
- Provider: Gemini or OpenRouter, set keys and models
- Hotkeys: change or reset
- Check for Updates
- Preferences: Start at Login, Language, Fallback to OpenRouter on Gemini errors, Open Accessibility Settings, Open Settings File
- About & Privacy

## Updates

Updates are delivered through GitHub Releases. The app checks automatically about every 6 hours and you can run Check for Updates from the menu.
The menu also shows update status and the last check time.
Use Check for Updates -> Check to run it manually.

## CI/CD and Release

- Pushes to `main` run CI on GitHub Actions to build and validate the app.
- Release workflow builds the app, generates the Sparkle appcast, and uploads release assets.
- Builds are created in CI to avoid storing artifacts in the repo.

## Advanced settings (optional)

Settings live in `~/Library/Application Support/TextPolish/settings.json` (open from the menu).

Per-app timing profiles (bundle id or app name keys):

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

Gemini fallback to OpenRouter on temporary errors (requires an OpenRouter key):

```json
{
  "fallbackToOpenRouterOnGeminiError": true
}
```

Force the correction language:

```json
{
  "correctionLanguage": "en-US"
}
```

## Security and Privacy

- Sends only the text you selected or the current input.
- No analytics or telemetry.
- API keys are stored in macOS Keychain.
- Your clipboard is restored after each correction.
- Language choice only guides the correction and does not translate your text.
- Updates are delivered via GitHub Releases and Sparkle.

## Troubleshooting

- No menu bar icon: open the app from /Applications and keep it running.
- Hotkeys do not work: grant Accessibility permission and focus the input field.
- Start at Login does not enable: install or move the app to /Applications first.
- Gemini says "model not found": use Provider -> Detect Gemini Model.
- Quota errors: switch provider or update your key.
- Check for Updates is disabled: this build does not have update info.

## Screenshot

![TextPolish menu bar preview](docs/screenshot.svg)

## Build from source

Developer notes live in docs/development.md.

## Contributing and Security

- Contributing guide: CONTRIBUTING.md
- Security policy: SECURITY.md

## License

MIT. See LICENSE.

## Credits

Creator: Kurniadi Ilham (https://github.com/kxxil01)
LinkedIn: https://linkedin.com/in/kurniadi-ilham
