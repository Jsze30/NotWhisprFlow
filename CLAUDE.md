# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

WhisperFlow is a native macOS menu-bar push-to-talk dictation app. Hold Fn, speak, release — audio is sent to a speech-to-text provider, optionally cleaned up by an LLM, then pasted into the focused app via simulated Cmd+V. Pure Swift / AppKit, no external Swift package dependencies.

## Build & run

```bash
make && ditto WhisperFlow.app /Applications/WhisperFlow.app   # always run together: rebuild + install into /Applications
make run        # builds + opens the local bundle
make clean      # nukes .build/ and WhisperFlow.app
swift build -c release   # plain SwiftPM build (no .app bundle, no codesign)
```

Always run `make` chained with `ditto` — a bare `make` leaves `/Applications/WhisperFlow.app` stale.

There is no test target. Requires Xcode command-line tools, macOS 13+. Built via SwiftPM (`Package.swift`) as a single executable target; the `bundle` target then (1) `rm -rf`s the old `.app`, (2) creates `Contents/MacOS` + `Contents/Resources`, (3) copies `Info.plist` and the `Resources/` assets (icon, `waveform.svg`, `click.mp3`) plus the universal `arm64+x86_64` binary in, and (4) `codesign`s the bundle with `SIGN_IDENTITY` (see below). This `.app` wrapper is what makes AppKit + TCC permissions work correctly. Every rebuild should be `make && ditto WhisperFlow.app /Applications/WhisperFlow.app` so the installed copy stays in sync.

**TCC / signing:** `make` signs the bundle with a stable **Apple Development** identity (auto-detected via `security find-identity`, overridable with `make SIGN_IDENTITY=...`). Because the code identity stays constant across rebuilds, macOS keeps the Microphone / Accessibility / Input Monitoring grants — you should only need to grant them once. The first `codesign` with a keychain identity may show a one-time "codesign wants to sign using key…" prompt; click **Always Allow**. If no Apple Development identity exists, the Makefile falls back to ad-hoc `--sign -`, which reverts to the old behaviour where every rebuild changes identity and silently revokes all three grants (re-grant in **System Settings → Privacy & Security**, then relaunch). Switching signing identity (e.g. ad-hoc → Apple Development) counts as a new identity, so that one transition still requires a re-grant.

## Architecture

`main.swift` boots `NSApplication` with `AppDelegate` as the orchestrator. The flow is:

1. **`HotkeyManager`** — push-to-talk via Fn. Uses `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` filtered to `keyCode == 63` (the Fn key itself). This intentionally ignores arrow keys / home / end / page-up-down — those keys assert the Fn modifier on their `keyDown` events but do **not** generate a flagsChanged event for keyCode 63. Requires Input Monitoring (and Accessibility for the monitor to receive global events). The same flagsChanged monitor also watches the **right Command key** (`keyCode == 54`): two down-edges within 0.4s fire `onToggleHide` to toggle hide mode. A lone modifier tap does nothing in other apps, so it never collides with editor/browser shortcuts.
2. **`AudioRecorder`** — captures mic audio via AVAudioEngine, accumulates 16 kHz / mono / int16 PCM into a WAV `Data` blob returned on `stop`. Also exposes `onLevel: (Float) -> Void` — fired on main each input buffer with a sqrt-curve-normalized peak amplitude (0...1) so the overlay can render an audio-reactive waveform.
3. **`OverlayWindow`** — always-visible floating pill at bottom-center of the screen. Solid black with a 1px white border, rounded to a perfect pill at every size. Four states (`OverlayState`):
   - `.idle` — tiny 28×6 pill (always shown when the app isn't dictating).
   - `.recording` — animates to 88×30 with 11 white bars whose heights track the live mic level history (rolling 11-slot buffer → bars appear to scroll left→right).
   - `.transcribing` — 88×30 with 3 white pulsing dots.
   - `.error(String)` — 88×30 with a single red dot (auto-reverts to `.idle` after 2s).
   - Pill size and corner radius animate together inside a single `CATransaction` (~120ms ease-out). Inner indicators are laid out without implicit animation and revealed after the resize to avoid center-line flashes. The pill is rendered as a `CALayer` inside a transparent borderless `NSPanel`.
   - **Hide mode** (`setHideWhenIdle`): when on, the idle pill is parked off-screen below the bottom edge and `orderOut`. Pressing Fn slides the whole panel up (`NSAnimationContext` on `panel.animator().setFrameOrigin`, ~220ms) while the pill expands; on return to `.idle` it slides back down and `orderOut`s. It stays visible through `.transcribing`, sinking only once the pill returns to idle. Persisted as `Config.hideMode`; toggled via the menu item or double-tapping the right Command key.
4. **`TranscriptionPipeline`** — provider auto-selected based on which API key is set:
   - **Deepgram (preferred when `deepgramApiKey` is present):** `POST https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true&punctuate=true&filler_words=false` with `Authorization: Token <KEY>` and the raw WAV as the body. Custom vocab terms (comma- or newline-split) are sent as repeated `keyterm=` query params.
   - **OpenAI fallback:** `POST /v1/audio/transcriptions` with `Config.data.transcriptionModel` (default `gpt-4o-transcribe`), falling back to `whisper-1` on failure. Custom vocab goes in the `prompt` field.
   - **Cleanup pass (optional):** if `enableCleanup` **and** an OpenAI key is set, `POST /v1/chat/completions` with `cleanupModel` (default `gpt-4o-mini`) strips fillers, applies spoken formatting commands (`new paragraph`, `comma`, etc.), and receives dictionary replacement hints. Skipped automatically when only the Deepgram key is configured — Deepgram's `smart_format` already punctuates. Cleanup failure is non-fatal — raw transcript is returned. Dictionary replacements are still applied deterministically after cleanup/raw transcription.
5. **`Paster`** — saves current pasteboard text, writes transcript, synthesizes Cmd+V via `CGEvent`, then restores previous clipboard ~0.4s later (text only — images/files are lost).

All networking uses raw `URLSession`; the OpenAI transcription request hand-builds a multipart body, the Deepgram request just streams the WAV. `Config` is a singleton JSON file at `~/Library/Application Support/WhisperFlow/config.json` with the following fields:

```json
{
  "apiKey": "",              // OpenAI; env fallback: OPENAI_API_KEY
  "deepgramApiKey": "",      // Deepgram;  env fallback: DEEPGRAM_API_KEY
  "customVocabulary": "",    // comma- or newline-separated terms
  "dictionaryReplacements": [], // [{ "word": "source", "replacement": "target" }]
  "transcriptionModel": "gpt-4o-transcribe",
  "cleanupModel": "gpt-4o-mini",
  "enableCleanup": true,
  "hideMode": false          // when true, the idle pill hides off-screen
}
```

Env-var fallback only applies when the corresponding field is empty in the JSON. Note that env vars are only inherited when launching the binary from a shell (`./WhisperFlow.app/Contents/MacOS/WhisperFlow`) — `open WhisperFlow.app` won't see them because launchd doesn't read `.env`.

## Permissions

The app needs three TCC grants — **Microphone**, **Accessibility** (to post synthetic Cmd+V *and* to receive `NSEvent` global monitor events), and **Input Monitoring** (for the Fn key detection). Mic access is requested explicitly in `applicationDidFinishLaunching`; the other two are triggered implicitly by first use and must be granted manually in System Settings. App must be relaunched after granting.

## Things to know when editing

- Push-to-talk key is wired to `HotkeyManager.fnKeyCode = 63`. Changing it means picking a different keyCode and (if it's not a modifier) replacing the flagsChanged monitor with `.keyDown`/`.keyUp` monitors.
- The README is slightly out of sync with the code (says Right-Option, code uses Fn). Update both together.
- `.app` bundle identity is set in `Resources/Info.plist`; rebuild with `make` after any change there.
- Clicking the menu bar icon opens a three-item menu: Dictionary, Hide Mode, and Quit. Dictionary opens the dictionary panel, which stores `dictionaryReplacements` in config. Hide Mode is a checkmark toggle mirroring `Config.hideMode` (also toggled by double-tapping the right Command key, keyCode 54, handled in `HotkeyManager`).
- Logs are written via `NSLog` and viewable in Console.app filtered on `WhisperFlow`, or by launching the binary directly from a terminal.
- Pill geometry constants live at the top of `OverlayWindow` (`expandedSize`, `idleSize`, `bottomOffset`) and inside `IndicatorView` (`barCount`, plus `barWidth`/`spacing`/`h` in `layoutBars`). All other layout (dots, error dot, corner radius) derives from `pillLayer.bounds`, so changing the pill size doesn't break the indicators.
- The log line `📡 sending N bytes to OpenAI` in `AppDelegate.stopRecording` is hardcoded — it fires regardless of which provider actually handles the request.
