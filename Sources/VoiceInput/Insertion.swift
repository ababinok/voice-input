import AppKit
import ApplicationServices
import VoiceInputCore

@MainActor
final class TextInsertion {
    struct Target {
        let pid: pid_t
        let field: AXUIElement?
        let screen: NSScreen
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    private func focusedField(_ pid: pid_t) -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func capture() -> Target? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var screen = NSScreen.main ?? NSScreen.screens[0]
        if AXIsProcessTrusted(), let window = attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
           CFGetTypeID(window) == AXUIElementGetTypeID(),
           let value = attribute(window as! AXUIElement, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            var point = CGPoint.zero
            if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let appPoint = NSPoint(x: point.x + 30, y: top - point.y - 30)
                screen = NSScreen.screens.first(where: { $0.frame.contains(appPoint) }) ?? screen
            }
        }
        return Target(pid: app.processIdentifier, field: AXIsProcessTrusted() ? focusedField(app.processIdentifier) : nil, screen: screen)
    }
    private func editable(_ field: AXUIElement) -> Bool {
        let role = attribute(field, kAXRoleAttribute) as? String ?? ""
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return false }
        if let enabled = attribute(field, kAXEnabledAttribute) as? Bool, !enabled { return false }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable)
        var selectedSettable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &selectedSettable)
        return settable.boolValue || selectedSettable.boolValue
    }
    func copyAndPaste(_ text: String, into target: Target?) async -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { return false }
        // Wait for the command key from the toggle shortcut to be released.
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !Task.isCancelled, let target, let original = target.field,
              let current = focusedField(target.pid) else { return false }
        let secure = (attribute(current, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole
        guard DeliveryPolicy.canPaste(trusted: AXIsProcessTrusted(),
                                      sameApp: NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid,
                                      sameField: CFEqual(original, current), editable: editable(current), secure: secure),
              CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        // Posting is a best-effort paste; text remains in the clipboard even if an editor rejects it.
        return true
    }
}
