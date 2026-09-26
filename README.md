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
- End your dictation with **"boom"** or **"press enter"** to omit the command and press Enter after pasting (for example, "See you soon. Boom.").
  Saying just "boom" or "press enter" presses Enter without pasting text.
- Say "one buy milk, two call Mom, three walk the dog" to paste a numbered list with each item on its own line.
  You can include an introductory sentence and closing prose, such as "Let's do this. One buy milk. Two call Mom. That's all for today."
  The introduction and closing text become separate paragraphs around the list.
  Inline introductions such as "Could you one, buy milk. Two, call Mom." also work when the numbers have punctuation or are spoken as "number one", "number two".
  Local detection uses sentence boundaries: the last item's first sentence ends the list, so keep that item to one sentence when adding a closing paragraph.
  This works locally with either transcription provider, including when AI cleanup is disabled.
- Filler words are stripped; spoken commands like "new paragraph", "comma", "question mark" are applied.
- **Hide mode:** by default the pill sits at the bottom of the screen. Toggle **Hide Mode** from the menu bar icon, or **double-tap the right Command key**, to hide it - then the pill only rises up from the bottom edge while you hold Fn and slides back down when you release. The setting persists across launches.

## Config

Stored at `~/Library/Application Support/WhisperFlow/config.json`. If `OPENAI_API_KEY` is set in the environment and no key is saved, it's used as fallback. Click the menu bar icon, then choose Dictionary to add replacements such as `word -> replacement`.

## Known limitations (MVP)

- No streaming partials yet (single request on release).
- Fn only; not customizable via UI.
- Restoring previous clipboard is best-effort (text only).
