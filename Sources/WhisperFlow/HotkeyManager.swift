import AppKit

/// Push-to-talk: hold Fn. Uses an NSEvent global monitor on flagsChanged filtered to
/// keyCode 63 (the Fn key itself) — arrows / home / end / page-up-down assert the Fn
/// modifier on their keyDown events but do NOT generate flagsChanged with keyCode 63,
/// so this naturally ignores them.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var monitor: Any?
    private var isDown = false
    private let fnKeyCode: UInt16 = 63

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        NSLog("[WhisperFlow] Hotkey monitor started — hold Fn to record.")
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == fnKeyCode else { return }
        let down = event.modifierFlags.contains(.function)
        if down && !isDown {
            isDown = true
            NSLog("[WhisperFlow] 🎙 Fn down")
            onPress?()
        } else if !down && isDown {
            isDown = false
            NSLog("[WhisperFlow] ⏹ Fn up")
            onRelease?()
        }
    }
}
