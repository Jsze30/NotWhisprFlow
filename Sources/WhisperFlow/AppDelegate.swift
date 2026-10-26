import AppKit
import AVFoundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkey: HotkeyManager!
    private var recorder: AudioRecorder!
    private var overlay: OverlayWindow!
    private var pipeline: TranscriptionPipeline!
    private var dictionaryWindow: NSWindow?
    private var dictionaryController: DictionaryPanelController?
    private var hideModeItem: NSMenuItem?
    private var isRecording = false
    /// Dictations whose paste has not yet been sent (excludes paste verification).
    private var pendingDictations = 0
    private var lastDelivery: Task<Void, Never>?
    /// Set for 2s after a failed dictation so the pill shows its red error dot.
    private var errorMessage: String?
    private var errorToken = 0
    private let clicks: ClickPlayer? = {
        let bundled = Bundle.main.url(forResource: "click", withExtension: "mp3")
        let source = URL(fileURLWithPath: "Resources/click.mp3", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        guard let url = bundled ?? (FileManager.default.fileExists(atPath: source.path) ? source : nil) else { return nil }
        return ClickPlayer(url: url, pressVolume: 0.4, releaseVolume: 0.4,
                           pressPitchCents: -1200, releasePitchCents: -1700)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.shared.load()

        statusItem = NSStatusBar.system.statusItem(withLength: 22)
        configureStatusItemIcon()
        configureStatusMenu()

        overlay = OverlayWindow()
        recorder = AudioRecorder()
        recorder.onLevel = { [weak self] level in self?.overlay.update(level: level) }
        pipeline = TranscriptionPipeline()

        // Trigger mic permission prompt on launch in case it hasn't fired yet.
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            NSLog("[WhisperFlow] mic access granted=%@", granted ? "YES" : "NO")
        }

        hotkey = HotkeyManager()
        hotkey.onPress = { [weak self] in
            self?.clicks?.playPress()
            self?.startRecording()
        }
        hotkey.onRelease = { [weak self] in
            self?.clicks?.playRelease()
            self?.stopRecording()
        }
        hotkey.onToggleHide = { [weak self] in self?.toggleHideMode() }
        hotkey.start()

        overlay.setHideWhenIdle(Config.shared.data.hideMode)
        overlay.show(state: .idle)
    }

    private func configureStatusItemIcon() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown

        let bundledURL = Bundle.main.url(forResource: "waveform", withExtension: "svg")
        let sourceURL = URL(fileURLWithPath: "Resources/waveform.svg", relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        guard let imageURL = bundledURL ?? (FileManager.default.fileExists(atPath: sourceURL.path) ? sourceURL : nil),
              let image = NSImage(contentsOf: imageURL) else {
            button.title = "WF"
            return
        }

        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        button.image = image
    }

    private func configureStatusMenu() {
        let menu = NSMenu()

        let dictionaryItem = NSMenuItem(title: "Dictionary", action: #selector(openDictionaryPanel), keyEquivalent: "")
        dictionaryItem.target = self
        menu.addItem(dictionaryItem)

        let hideItem = NSMenuItem(title: "Hide Mode", action: #selector(toggleHideMode), keyEquivalent: "")
        hideItem.target = self
        hideItem.state = Config.shared.data.hideMode ? .on : .off
        menu.addItem(hideItem)
        hideModeItem = hideItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openDictionaryPanel() {
        let controller: DictionaryPanelController
        if let existing = dictionaryController {
            controller = existing
        } else {
            let created = DictionaryPanelController()
            dictionaryController = created
            controller = created
        }

        let window: NSWindow
        if let existing = dictionaryWindow {
            window = existing
        } else {
            let created = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            created.title = "Dictionary"
            created.contentViewController = controller
            created.isReleasedWhenClosed = false
            created.center()
            dictionaryWindow = created
            window = created
        }

        controller.reloadReplacements()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func startRecording() {
        guard !isRecording else { return }
        guard !Config.shared.apiKey.isEmpty || !Config.shared.deepgramApiKey.isEmpty else {
            NSLog("[WhisperFlow] ❌ no API key in config (need OpenAI or Deepgram)")
            NSSound.beep()
            return
        }
        isRecording = true
        overlay.show(state: .recording)
        Paster.prepareFrontmostApplication()
        do {
            try recorder.start()
            NSLog("[WhisperFlow] 🎙 recording started")
        } catch {
            isRecording = false
            refreshOverlay()
            NSLog("[WhisperFlow] ❌ recorder start failed: \(error)")
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        pendingDictations += 1
        refreshOverlay()
        let wav = recorder.stop()
        let pipeline = self.pipeline!
        let transcription = Task.detached { () -> Result<DictationResult, Error>? in
            guard wav.count > 4096 else { return nil }
            NSLog("[WhisperFlow] 📡 sending %d bytes to OpenAI", wav.count)
            do { return .success(try await pipeline.process(wav: wav)) } catch { return .failure(error) }
        }
        // Earlier dictations may still be transcribing. Chain each paste behind the
        // previous one so text lands in the order it was spoken.
        let previous = lastDelivery
        lastDelivery = Task {
            await previous?.value
            var finishedDisplaying = false
            let finishDisplaying = {
                guard !finishedDisplaying else { return }
                finishedDisplaying = true
                self.pendingDictations -= 1
                self.refreshOverlay()
            }
            await deliver(await transcription.value, onPastePosted: finishDisplaying)
            // Errors, empty transcripts, and canceled pastes never post Cmd+V.
            finishDisplaying()
        }
    }

    private func deliver(_ outcome: Result<DictationResult, Error>?,
                         onPastePosted: @escaping () -> Void) async {
        switch outcome {
        case nil:
            NSLog("[WhisperFlow] ⚠️ audio too short")
        case .success(let result):
            NSLog("[WhisperFlow] ✅ transcript: %@", result.text)
            await withCheckedContinuation { cont in
                Paster.paste(result.text, pressEnter: result.pressEnter,
                             onPastePosted: onPastePosted) { _ in cont.resume() }
            }
        case .failure(PipelineError.empty):
            NSLog("[WhisperFlow] ⚠️ no speech transcribed")
        case .failure(let error):
            NSLog("[WhisperFlow] ❌ pipeline failed: %@", "\(error)")
            errorToken += 1
            let token = errorToken
            errorMessage = error.localizedDescription
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard self.errorToken == token else { return }
                self.errorMessage = nil
                self.refreshOverlay()
            }
        }
    }

    /// The pill reflects the newest activity: recording wins, then any dictation still in flight.
    private func refreshOverlay() {
        if isRecording {
            overlay.show(state: .recording)
        } else if pendingDictations > 0 {
            overlay.show(state: .transcribing)
        } else if let errorMessage {
            overlay.show(state: .error(errorMessage))
        } else {
            overlay.hide()
        }
    }

    @objc private func toggleHideMode() {
        var newData = Config.shared.data
        newData.hideMode.toggle()
        Config.shared.save(newData)
        overlay.setHideWhenIdle(newData.hideMode)
        hideModeItem?.state = newData.hideMode ? .on : .off
        NSLog("[WhisperFlow] hide mode %@", newData.hideMode ? "ON" : "OFF")
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
