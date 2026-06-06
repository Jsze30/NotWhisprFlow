import AppKit

enum Paster {
    static func paste(_ text: String) {
        let textToPaste = textEndsWithWhitespace(text) ? text : text + " "
        NSLog("[WhisperFlow] paste request len=%d preview=%@", textToPaste.count, String(textToPaste.prefix(60)))
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)

        pb.clearContents()
        let ok = pb.setString(textToPaste, forType: .string)
        NSLog("[WhisperFlow] clipboard write ok=%@", ok ? "YES" : "NO")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            simulateCmdV()
            NSLog("[WhisperFlow] Cmd+V posted")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let previous {
                    pb.clearContents()
                    pb.setString(previous, forType: .string)
                }
            }
        }
    }

    private static func textEndsWithWhitespace(_ text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(last)
    }

    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // ANSI 'V'

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
