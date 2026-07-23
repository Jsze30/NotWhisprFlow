import AppKit

/// Push-to-talk: hold Fn. Uses an NSEvent global monitor on flagsChanged filtered to
/// keyCode 63 (the Fn key itself) — arrows / home / end / page-up-down assert the Fn
/// modifier on their keyDown events but do NOT generate flagsChanged with keyCode 63,
/// so this naturally ignores them.
final class HotkeyManager {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Fired when the right Command key is tapped twice in quick succession.
    var onToggleHide: (() -> Void)?

    private var monitor: Any?
    private var isDown = false
    private let fnKeyCode: UInt16 = 63

    // Double-tap Right Command → toggle hide mode. keyCode 54 is the right ⌘
    // (left ⌘ is 55). A lone modifier tap does nothing in other apps, so this
    // never collides with editor/browser shortcuts.
    private let rightCommandKeyCode: UInt16 = 54
    private var isRightCommandDown = false
    private var lastRightCommandTap: TimeInterval = 0
    private let doubleTapThreshold: TimeInterval = 0.4

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        NSLog("[WhisperFlow] Hotkey monitor started — hold Fn to record, double-tap right ⌘ to toggle hide mode.")
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case fnKeyCode: handleFn(event)
        case rightCommandKeyCode: handleRightCommand(event)
        default: break
        }
    }

    private func handleFn(_ event: NSEvent) {
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

    private func handleRightCommand(_ event: NSEvent) {
        let down = event.modifierFlags.contains(.command)
        if down && !isRightCommandDown {
            isRightCommandDown = true
            let now = event.timestamp
            if now - lastRightCommandTap <= doubleTapThreshold {
                lastRightCommandTap = 0
                NSLog("[WhisperFlow] ⌘⌘ right-command double-tap → toggle hide mode")
                onToggleHide?()
            } else {
                lastRightCommandTap = now
            }
        } else if !down && isRightCommandDown {
            isRightCommandDown = false
        }
    }
}
