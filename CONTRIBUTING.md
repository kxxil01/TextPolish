# Contributing

Thanks for your interest in TextPolish.

## Quick start

```bash
./scripts/build_app.sh
open ./build/TextPolish.app
```

## Development

```bash
swift build -c release
swift run -c release TextPolish
```

Tests:

```bash
swift test
```

Note: tests require XCTest (Xcode toolchain on macOS).

## Guidelines

- Keep the app small and fast. Avoid heavy dependencies.
- Preserve minimal edits and original tone in prompts.
- Keep UI work on the main actor and network work async.
- Do not commit build artifacts (`build/`, `.build/`).

## Releases

- Update version values in `scripts/build_app.sh` to match the release tag.
- Use the release workflow to build artifacts and appcast.
