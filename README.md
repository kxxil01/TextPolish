# TextPolish

**Fix grammar and typos in any app with a keyboard shortcut.**

A small, fast menu bar app for macOS. Works in Discord, Slack, emails, or any text field. Your clipboard is restored after each correction.

![TextPolish menu bar preview](docs/screenshot.svg)

[![CI](https://github.com/kxxil01/TextPolish/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/kxxil01/TextPolish/actions/workflows/ci.yml)
[![Release](https://github.com/kxxil01/TextPolish/actions/workflows/release.yml/badge.svg?event=release)](https://github.com/kxxil01/TextPolish/actions/workflows/release.yml)

## Recent Updates

**Latest (Jan 2025):** Major code refactoring — Extracted 369 lines of duplicate code into shared `TextProcessor` protocol, improving maintainability while preserving 100% test coverage (135/135 tests passing).

**Previous:** Added tone analysis feature — analyze the tone of your text with detailed insights.

**Website:** [textpolish.pages.dev](https://textpolish.pages.dev)

---

## Download

**Homebrew (recommended):**

```bash
brew install --cask kxxil01/tap/textpolish
```

**Manual download:** [Latest release](https://github.com/kxxil01/TextPolish/releases)

- `TextPolish.pkg` — installer (recommended)
- `TextPolish.app.zip` — drag to Applications

**🌐 Website & Documentation:** [textpolish.pages.dev](https://textpolish.pages.dev)

---

## Setup (3 steps)

### 1. Open the app

After installing, open TextPolish from Applications. You'll see a small icon in your menu bar (top-right of your screen).

### 2. Allow Accessibility

TextPolish needs permission to send keyboard shortcuts (copy/paste) to other apps.

**System Settings → Privacy & Security → Accessibility → Enable TextPolish**

### 3. Add your API key (free)

TextPolish supports 4 providers. Add at least one API key to get started:

**Option A: Gemini (Google AI, recommended)**
1. Go to [aistudio.google.com/apikey](https://aistudio.google.com/app/apikey)
2. Click "Create API Key" — **free, no credit card needed**
3. Copy the key
4. In TextPolish menu: **Provider → Set Gemini API Key...** → paste → Save

> Free tier includes ~15 requests/minute, ~1500/day. Plenty for normal use.

**Option B: OpenRouter**
1. Go to [openrouter.ai/keys](https://openrouter.ai/keys) and sign up
2. Create an API key
3. In TextPolish menu: **Provider → OpenRouter** → **Set OpenRouter API Key...**

> The default model is free. No credits needed unless you switch to a paid model.

**Option C: OpenAI**
1. Go to [platform.openai.com/api-keys](https://platform.openai.com/api-keys)
2. Create a new secret key
3. In TextPolish menu: **Provider → OpenAI** → **Set OpenAI API Key...**

**Option D: Anthropic**
1. Go to [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
2. Create an API key
3. In TextPolish menu: **Provider → Anthropic** → **Set Anthropic API Key...**

That's it! You're ready to use TextPolish.

---

## Supported Providers

- Gemini (Google AI)
- OpenRouter
- OpenAI
- Anthropic

---

## How to Use

### Keyboard Shortcuts

| Action | Shortcut | What it does |
|--------|----------|--------------|
| **Correct Selection** | `⌃⌥⌘G` | Fixes the text you've selected |
| **Correct All** | `⌃⌥⌘⇧G` | Selects all text in the field, then fixes it |

> **Tip:** `⌃⌥⌘G` means hold Control + Option + Command, then press G.

### Or Use the Menu

Click the TextPolish icon in your menu bar and choose:
- **Correct Selection** — fix selected text
- **Correct All** — fix everything in the text field

### What Happens

1. TextPolish copies your text
2. Sends it to the AI for correction
3. Pastes the corrected text back
4. Restores your original clipboard

The icon shows a badge with how many corrections you've made today.

### Tone Analysis

Analyze the tone and sentiment of your text:

1. **Select your text** in any app
2. **Use menu:** Click TextPolish icon → **Tone Analysis**
3. **View results:** Get detailed insights about:
   - Overall tone (formal, casual, friendly, etc.)
   - Sentiment (positive, neutral, negative)
   - Writing style suggestions
   - Readability metrics

---

## Features

- **Works everywhere** — Discord, Slack, Gmail, Notes, any app with a text field
- **Keeps your voice** — minimal edits, no AI rewriting your tone
- **Preserves formatting** — line breaks, markdown, emojis stay intact
- **Tone analysis** — analyze text tone and sentiment with detailed insights
- **Clipboard safe** — your clipboard is always restored
- **Privacy focused** — no analytics, keys stored in macOS Keychain
- **Auto-updates** — get new versions automatically

---

## Settings

Click the menu bar icon to access:

| Setting | What it does |
|---------|--------------|
| **Provider** | Switch between Gemini, OpenRouter, OpenAI, and Anthropic |
| **Tone Analysis** | Analyze text tone and sentiment |
| **Hotkeys** | Change or reset keyboard shortcuts |
| **Language** | Force English (US) or Indonesian |
| **Start at Login** | Launch automatically when you log in |
| **Check for Updates** | Manually check for new versions |

---

## Troubleshooting

**No menu bar icon?**
→ Open TextPolish from Applications. Keep it running.

**Shortcuts don't work?**
→ Check Accessibility permission in System Settings.
→ Make sure you're focused on a text field.

**"Model not found" error?**
→ Menu → Provider → Detect Gemini Model

**Quota/rate limit error (429)?**
→ You've hit the free tier limit. Wait a minute and try again.
→ Or enable provider fallback (automatic backup is available for all provider combinations).

**Start at Login won't enable?**
→ Move the app to /Applications first.

---

## Privacy & Security

- **Only sends your selected text** — nothing else
- **No analytics or tracking** — zero telemetry
- **API keys in Keychain** — securely stored by macOS
- **Open source** — review the code yourself

---

## For Developers

- [Development guide](docs/development.md)
- [Contributing](CONTRIBUTING.md)
- [Agent notes](AGENTS.md)
- [Website & Docs](https://textpolish.pages.dev)

---

## License

MIT — see [LICENSE](LICENSE)

## Credits

Created by [Kurniadi Ilham](https://github.com/kxxil01) · [LinkedIn](https://linkedin.com/in/kurniadi-ilham)
