# WhisperFlow

A native macOS menu-bar dictation app: hold a key, speak, release — transcribed text is pasted into the focused app via OpenAI Whisper + GPT-4o-mini cleanup.

## Build

```bash
make           # builds WhisperFlow.app (universal, ad-hoc signed)
make run       # builds and launches
```

Requires Xcode command-line tools and macOS 13+.

## First run

1. Launch `WhisperFlow.app`. A waveform icon appears in the menu bar.
2. Settings open automatically. Paste your OpenAI API key. Add custom vocab if desired.
3. macOS will prompt for **Microphone**, **Accessibility**, and **Input Monitoring** permissions. Grant all three (System Settings → Privacy & Security).
4. Restart the app after granting permissions (TCC quirk).

## Usage

- **Hold Fn** to record. An overlay appears.
- **Release** to transcribe + auto-paste into whatever app is focused.
- Filler words are stripped; spoken commands like "new paragraph", "comma", "question mark" are applied.

## Config

Stored at `~/Library/Application Support/WhisperFlow/config.json`. If `OPENAI_API_KEY` is set in the environment and no key is saved, it's used as fallback. Click the menu bar icon, then choose Dictionary to add replacements such as `word -> replacement`.

## Known limitations (MVP)

- No streaming partials yet (single request on release).
- Fn only; not customizable via UI.
- Restoring previous clipboard is best-effort (text only).
