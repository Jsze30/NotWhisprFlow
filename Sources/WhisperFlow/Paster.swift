import AppKit

enum Paster {
    /// Accessibility is optional evidence, never a prerequisite for Cmd+V.
    struct Destination {
        var applicationID: pid_t?
        var isTextInput: Bool
        var value: () -> String?
    }

    struct Environment {
        var pasteboard: NSPasteboard = .general
        var destination: () -> Destination = { currentDestination() }
        var frontmostApplicationID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        var postPaste: () -> Void = { simulateCmdV() }
        var postEnter: () -> Void = { simulateEnter() }
        var schedule: (TimeInterval, @escaping () -> Void) -> Void = { delay, action in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }

    static func paste(_ text: String, pressEnter: Bool = false,
                      environment: Environment = Environment(),
                      completion: @escaping (Bool) -> Void = { _ in }) {
        guard !text.isEmpty else {
            if pressEnter { environment.postEnter() }
            completion(true)
            return
        }
        let textToPaste = pressEnter || textEndsWithWhitespace(text) ? text : text + " "
        let destination = environment.destination()
        let pb = environment.pasteboard
        // Keep the dictation available for manual Cmd+V even if automatic paste fails.
        pb.clearContents()
        guard pb.setString(textToPaste, forType: .string) else {
            completion(false)
            return
        }
        let changeCount = pb.changeCount
        environment.schedule(0.15) {
            // Protect against switching apps or copying something during the delay.
            // AX element identity is not stable in web/custom editors.
            guard pb.changeCount == changeCount,
                  destination.applicationID == environment.frontmostApplicationID() else {
                completion(false)
                return
            }
            let before = destination.value()
            environment.postPaste()
            environment.schedule(0.4) {
                let after = destination.value()
                let confirmed = insertionConfirmed(before: before, after: after, text: text)
                // A recognized editor with unavailable values cannot be checked.
                // Preserve normal paste behavior in those editors instead of
                // treating missing accessibility data as a failed paste.
                let accepted = confirmed || (destination.isTextInput && (before == nil || after == nil))
                if pressEnter, accepted,
                   destination.applicationID == environment.frontmostApplicationID() {
                    environment.postEnter()
                }
                completion(accepted)
            }
        }
    }

    private static func currentDestination() -> Destination {
        let appID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let target = focusedElement() else {
            return Destination(applicationID: appID, isTextInput: false, value: { nil })
        }
        let role = attribute(target, kAXRoleAttribute) as? String
        let isTextInput = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "")
            || attribute(target, kAXSelectedTextRangeAttribute) != nil
            || attribute(target, "AXEditable") as? Bool == true
        return Destination(applicationID: appID, isTextInput: isTextInput,
                           value: { attribute(target, kAXValueAttribute) as? String })
    }

    static func insertionConfirmed(before: String?, after: String?, text: String) -> Bool {
        guard let before, let after, before != after, !text.isEmpty else { return false }
        // Require a new occurrence, so unrelated edits to a field that already
        // contains this phrase cannot be mistaken for a successful paste.
        return after.components(separatedBy: text).count > before.components(separatedBy: text).count
    }

    private static func focusedElement() -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
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

    private static func simulateEnter() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let returnKey: CGKeyCode = 0x24
        let down = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)
        down?.flags = []
        up?.flags = []
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
