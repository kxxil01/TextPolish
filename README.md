# TextPolish (macOS)

Small, fast menu bar app that fixes grammar/typos in any app (e.g. Discord) via global shortcuts, while preserving formatting and keeping edits minimal (no “AI rewrite” tone).

## Current State (MVP)

- Menu-bar only app (no Dock icon) with two global shortcuts.
- Backends: **Gemini** (default) + **OpenRouter** (optional).
- API keys are entered in-app and stored in **macOS Keychain** (service: `com.kxxil01.TextPolish`, with legacy read/migration from `com.ilham.GrammarCorrection`).
- “Start at Login” toggle (most reliable when installed in `/Applications`).
- Sparkle-based auto updates via GitHub Releases.
- Hotkeys configurable from the menu (with conflict checks).
- `.pkg` installer builds and installs to `/Applications/TextPolish.app` and auto-launches after install.

Shortcuts:

- **Correct Selection:** `⌃⌥⌘G`
- **Correct All:** `⌃⌥⌘⇧G` (does `⌘A` first — put your cursor in the input box)

It works by copying your text, sending it to the selected backend (Gemini or OpenRouter), pasting the corrected result back, then restoring your original clipboard.

## Download (Recommended)

Get the latest release from:

https://github.com/kxxil01/TextPolish/releases

Choose:

- `TextPolish.app.zip` for drag-and-drop install (unzip and move to `/Applications`).
- `TextPolish.pkg` for a guided installer.

## Quick Start

1. Download the latest release and move `TextPolish.app` to `/Applications`.
2. Open the app from `/Applications`. The menu bar icon appears.
3. Grant Accessibility permission: System Settings -> Privacy & Security -> Accessibility -> TextPolish.
4. Set your API key from the menu: Backend -> Set Gemini API Key...
5. Use `Ctrl+Option+Command+G` for selection or `Ctrl+Option+Command+Shift+G` for all.
6. Use the menu bar icon to switch backends, adjust hotkeys, and check for updates.

## Screenshot

![TextPolish menu bar preview](docs/screenshot.svg)

## Build

```bash
./scripts/build_app.sh
open ./build/TextPolish.app  # or the path printed by the script
```

## Dev (SwiftPM)

```bash
swift build -c release
swift run -c release TextPolish
```

## Installer (.pkg)

If you prefer an installer that drops the app into `/Applications`:

```bash
./scripts/build_pkg.sh
open ./build/TextPolish.pkg
```

This installs to: `/Applications/TextPolish.app`

The installer will also launch the app after installation (menu bar icon appears).

## Updates (Sparkle)

The app checks GitHub Releases for updates and can install them without a separate server.
Automatic checks run about every 6 hours, and there is a menu item for manual checks.

Updates use the `TextPolish.app.zip` asset. The `.pkg` remains for manual installs.

Local/dev builds without Sparkle keys keep updates disabled.

Maintainer setup:

- Run `./scripts/sparkle_generate_keys.sh` to generate Sparkle keys (Keychain prompt). The public key prints to stdout, and the private key is saved to `.sparkle/private_key`.
- Add `SPARKLE_PUBLIC_KEY` as a GitHub repository variable.
- Add `SPARKLE_PRIVATE_KEY` as a GitHub Actions secret (the contents of `.sparkle/private_key`).
- Add signing secrets to GitHub Actions: `MACOS_SIGNING_CERT_P12_BASE64`, `MACOS_SIGNING_CERT_PASSWORD`, `MACOS_KEYCHAIN_PASSWORD`, `CODESIGN_IDENTITY`.
- Sign releases with a stable Developer ID Application certificate (Sparkle requires consistent code signing across updates).
- Create a GitHub Release. CI uploads `appcast.xml` and the app uses it for periodic checks.

Manual checks are available from the menu item "Check for Updates...".

### Free Signing (No Apple Developer Account)

Sparkle only needs a consistent signing identity. You can use a self-signed code signing certificate for free.
For self-signed certs, the build script disables hardened runtime automatically so Sparkle can load.

Create the certificate:

1. Open Keychain Access.
2. Certificate Assistant -> Create a Certificate.
3. Name it `TextPolish Local` (any name is fine).
4. Identity Type: `Self Signed Root`.
5. Certificate Type: `Code Signing`.
6. Save to the login keychain.

Export and set secrets:

```bash
security find-identity -v -p codesigning
base64 -i /path/to/TextPolish.p12 | tr -d '\n'
openssl rand -hex 16
```

Set GitHub Actions secrets:

- `MACOS_SIGNING_CERT_P12_BASE64`: base64 of the exported `.p12`
- `MACOS_SIGNING_CERT_PASSWORD`: the export password
- `MACOS_KEYCHAIN_PASSWORD`: any random string
- `CODESIGN_IDENTITY`: the exact name from `security find-identity`

## Permissions

The app needs **Accessibility** permission to trigger `⌘C/⌘V/⌘A` in Discord:

- System Settings → Privacy & Security → Accessibility → enable `TextPolish`

## Menu / Settings

You can change the correction backend from the menu bar icon:

- Backend → Gemini
- Backend → OpenRouter

API keys are entered in-app and stored in **Keychain**:

- Backend → Set Gemini API Key…
- Backend → Set Gemini Model…
- Backend → Detect Gemini Model…
- Backend → Set OpenRouter API Key…
- Backend → Set OpenRouter Model…
- Backend → Detect OpenRouter Model…
- Hotkeys → Set Correct Selection Hotkey… / Set Correct All Hotkey… / Reset to Defaults
- Check for Updates…
- Start at Login (toggles launch on startup)
- Privacy… (explains what is sent and what is stored)
- About TextPolish…
- Reveal App in Finder…

Advanced settings (timeouts, tuning) are optional and stored in:

- `~/Library/Application Support/TextPolish/settings.json`

Useful fields:

- `provider`: `"gemini"` (default) or `"openRouter"`

### Timing (Optional)

These are in milliseconds, for slower or faster target apps:

- `activationDelayMilliseconds`: delay after activation before typing
- `selectAllDelayMilliseconds`: delay after `⌘A`
- `copySettleDelayMilliseconds`: delay after `⌘C` before reading clipboard
- `copyTimeoutMilliseconds`: max wait for clipboard change
- `pasteSettleDelayMilliseconds`: delay after writing clipboard before `⌘V`
- `postPasteDelayMilliseconds`: delay after `⌘V` before restore

### Gemini

To use Gemini, set (in `settings.json` if you want to tune behavior):

- `provider`: `"gemini"`
- `geminiApiKey`: optional legacy fallback (prefer Keychain via menu or env `GEMINI_API_KEY` / `GOOGLE_API_KEY`)
- `geminiModel`: e.g. `"gemini-2.0-flash-lite-001"`
- `geminiBaseURL`: default `"https://generativelanguage.googleapis.com"`
- `geminiMinSimilarity`: default `0.65` (higher = less rewriting)
- `geminiMaxAttempts`: default `2` (retries if output rewrites too much)
- `geminiExtraInstruction`: optional extra rule (keeps edits minimal by default)

### OpenRouter

To use OpenRouter:

- `provider`: `"openRouter"`
- API key: prefer Keychain via menu (or env `OPENROUTER_API_KEY`)
- `openRouterModel`: e.g. `"meta-llama/llama-3.2-3b-instruct:free"`, `"google/gemini-2.0-flash-lite-001"`, `"openai/gpt-4o-mini"`
- `openRouterBaseURL`: default `"https://openrouter.ai/api/v1"`
- `openRouterMinSimilarity`: default `0.65` (higher = less rewriting)
- `openRouterMaxAttempts`: default `2`
- `openRouterExtraInstruction`: optional extra rule

## Troubleshooting

- Hotkeys don’t work: grant Accessibility permission (above) and ensure Discord’s input has focus.
- Installed the `.pkg` but can’t find the app: look in `/Applications/TextPolish.app`.
- Start at Login won’t enable: install/move the app into `/Applications` first.
- Gemini 404 “model not found”: use Backend → Detect Gemini Model… (or set a different model).
- Gemini 429 quota exceeded: switch Backend → OpenRouter (or use a billed Gemini key).
- Key doesn’t “save”: macOS may show a Keychain prompt; allow it (the app is brought to front to make the prompt visible).
- Check for Updates is disabled: local builds without Sparkle keys keep updates off.

## Roadmap (Recommended Next Features)
- Optional preview popover (“apply” / “cancel”) for safety.
- Request throttling/debounce + cancellation (avoid stacked corrections).
- Smarter clipboard/copy detection + per-app timing profiles (Discord vs others).
- Better provider fallback (e.g. auto-switch to OpenRouter on Gemini 429).
- Provider/model presets for “minimal edits” vs “more strict” modes.

## Cleanup (Dev / Reset)

To remove the app + local settings + Keychain items and reset build artifacts:

```bash
./scripts/cleanup_all.sh
```

## Credits

Creator: Kurniadi Ilham — github.com/kxxil01

## Trusted Distribution (No App Store)

You can make the app feel “trusted” without the App Store, but macOS **Gatekeeper trust** (no warnings on downloaded apps) requires **Developer ID + notarization** (paid). If you don’t want to pay, use options 2–4 below.

### Option 2 (Free): Build Locally (Best for Personal Use)

If you build the `.app` on your own Mac, it usually won’t be quarantined, so you typically won’t see “unidentified developer” warnings.

```bash
./scripts/build_app.sh
open ./build/TextPolish.app  # or the path printed by the script
```

### Option 3 (Free): Remove Quarantine (For Sharing Internally)

Downloaded apps are often quarantined. Removing quarantine bypasses Gatekeeper checks (works for internal use; less “professional”).

```bash
xattr -dr com.apple.quarantine ./TextPolish.app
open ./TextPolish.app
```

### Option 4 (Free): Sign with a Local Certificate (Improves Keychain UX)

Signing with your own **local code-signing certificate** can make Keychain access feel more consistent (stable app identity), even though it still won’t be Gatekeeper-trusted like notarization.

- Create a local “Code Signing” certificate in **Keychain Access** (Certificate Assistant → Create a Certificate…).
- Then sign:

```bash
codesign --force --deep --options runtime --sign "YOUR LOCAL CERT NAME" ./build/TextPolish.app  # or the path printed by build_app.sh
```

### Option 1 (Paid): Developer ID + Notarization (Best UX)

This is the only way to avoid Gatekeeper warnings for downloaded apps and to ship a “professional” build broadly.

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials "TextPolishNotary" --apple-id "you@example.com" --team-id "TEAMID" --password "APP_SPECIFIC_PASSWORD"
export NOTARY_PROFILE="TextPolishNotary"
./scripts/sign_and_notarize.sh
spctl --assess --type execute --verbose=4 ./build/TextPolish.app  # or the path printed by sign_and_notarize.sh
```
