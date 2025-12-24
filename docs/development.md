# Development

This document is for maintainers and contributors.

## Build

```bash
./scripts/build_app.sh
open ./build/TextPolish.app
```

## SwiftPM (Dev)

```bash
swift build -c release
swift run -c release TextPolish
```

## Settings (Advanced)

Settings live in `~/Library/Application Support/TextPolish/settings.json`.

- `timingProfiles`: per-app overrides for copy/paste timings. Keys can be bundle identifiers or app names.
- `fallbackToOpenRouterOnGeminiError`: retry with OpenRouter on Gemini request failures (429, 5xx, network).
- `correctionLanguage`: force the correction language (`auto`, `en-US`, `id-ID`).

## Installer (.pkg)

```bash
./scripts/build_pkg.sh
open ./build/TextPolish.pkg
```

## Updates (Sparkle)

TextPolish uses Sparkle + GitHub Releases for updates.

- Generate keys:
  ```bash
  ./scripts/sparkle_generate_keys.sh
  ```
  The public key prints to stdout. The private key is saved to `.sparkle/private_key`.

- Set repository values:
  - Variable: `SPARKLE_PUBLIC_KEY`
  - Secret: `SPARKLE_PRIVATE_KEY`

- Set signing secrets:
  - `MACOS_SIGNING_CERT_P12_BASE64`
  - `MACOS_SIGNING_CERT_PASSWORD`
  - `MACOS_KEYCHAIN_PASSWORD`
  - `CODESIGN_IDENTITY`

- Create a GitHub Release tag (for example, `v0.0.1`).
  CI builds `TextPolish.app.zip`, generates `appcast.xml`, and uploads assets.

## Free Signing (No Apple Developer Account)

Sparkle only needs a consistent signing identity. You can use a self-signed code signing certificate for free.
For self-signed certs, the build script disables hardened runtime automatically so Sparkle can load.

Create the certificate:

1. Open Keychain Access.
2. Certificate Assistant -> Create a Certificate.
3. Name it `TextPolish Local` (any name is fine).
4. Identity Type: Self Signed Root.
5. Certificate Type: Code Signing.
6. Save to the login keychain.

Export and set secrets:

```bash
security find-identity -v -p codesigning
base64 -i /path/to/TextPolish.p12 | tr -d '\n'
openssl rand -hex 16
```

## Notarization (Optional)

Developer ID + notarization is the best user experience for distributed builds:

```bash
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials "TextPolishNotary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "APP_SPECIFIC_PASSWORD"
export NOTARY_PROFILE="TextPolishNotary"
./scripts/sign_and_notarize.sh
```

## Cleanup

```bash
./scripts/cleanup_all.sh
```
