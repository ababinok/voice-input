import AppKit
import ApplicationServices
import OSLog
import VoiceInputCore

@MainActor
final class TextInsertion {
    private let logger = Logger(subsystem: "local.voiceinput.app", category: "TextInsertion")
    private func diagnostic(_ message: String) {
        // Only structural metadata: never record dictated text, field values, titles or URLs.
        logger.notice("\(message, privacy: .public)")
    }
    private func refused(_ reason: String) -> Bool {
        diagnostic("paste refused: \(reason)")
        return false
    }
    struct Target {
        let pid: pid_t
        let field: AXUIElement?
        let screen: NSScreen
    }
    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard error == .success else {
            diagnostic("AX read attribute=\(name) error=\(error.rawValue)")
            return nil
        }
        return value
    }
    private func focusedField(_ pid: pid_t) -> AXUIElement? {
        guard let value = attribute(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func focusedWindow(_ application: AXUIElement) -> AXUIElement? {
        guard let value = attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func capture(application app: NSRunningApplication?) async -> Target? {
        guard let app,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            diagnostic("capture: no frontmost application")
            return nil
        }
        let trusted = AXIsProcessTrusted()
        let application = AXUIElementCreateApplication(app.processIdentifier)
        // Chromium activates native accessibility when an AT reads the application role.
        // Do this before requesting focus; renderer accessibility can arrive asynchronously.
        if trusted { _ = attribute(application, kAXRoleAttribute) }
        let window = trusted ? focusedWindow(application) : nil
        var screen = NSScreen.main ?? NSScreen.screens[0]
        if let window,
           let value = attribute(window, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            var point = CGPoint.zero
            if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
                let top = NSScreen.screens.first?.frame.maxY ?? 0
                let appPoint = NSPoint(x: point.x + 30, y: top - point.y - 30)
                screen = NSScreen.screens.first(where: { $0.frame.contains(appPoint) }) ?? screen
            }
        }
        var field = trusted ? focusedField(app.processIdentifier) : nil
        // Only retry a missing field, never replace an already captured element.
        // A stable window is required so a delayed result cannot target another window.
        if trusted, field == nil, let window {
            let browserIDs: Set<String> = ["ru.yandex.desktop.yandex-browser", "com.google.Chrome",
                                          "org.chromium.Chromium", "com.microsoft.edgemac",
                                          "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
            if browserIDs.contains(app.bundleIdentifier ?? "") {
                // Chromium debounces this request for two seconds on modern macOS.
                // Request once, not on each retry (which would restart the debounce).
                let error = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
                diagnostic("accessibility activation pid=\(app.processIdentifier) error=\(error.rawValue)")
            }
            field = await FocusCapture.retry(attempts: 25, isCurrent: {
                guard AXIsProcessTrusted(),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                      let currentWindow = self.focusedWindow(application) else { return false }
                return CFEqual(window, currentWindow)
            }, read: {
                self.focusedField(app.processIdentifier)
            }, wait: {
                try await Task.sleep(for: .milliseconds(100))
            })
        }
        guard !Task.isCancelled else { return nil }
        diagnostic("capture pid=\(app.processIdentifier) trusted=\(trusted) fieldFound=\(field != nil)")
        return Target(pid: app.processIdentifier, field: field, screen: screen)
    }
    private func editable(_ field: AXUIElement) -> Bool {
        let role = attribute(field, kAXRoleAttribute) as? String ?? ""
        diagnostic("field role=\(role)")
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else {
            diagnostic("editable: unsupported role")
            return false
        }
        if let enabled = attribute(field, kAXEnabledAttribute) as? Bool, !enabled {
            diagnostic("editable: disabled field")
            return false
        }
        var settable = DarwinBoolean(false)
        let valueError = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable)
        var selectedSettable = DarwinBoolean(false)
        let selectedError = AXUIElementIsAttributeSettable(field, kAXSelectedTextAttribute as CFString, &selectedSettable)
        diagnostic("editable valueSettable=\(settable.boolValue) valueError=\(valueError.rawValue) selectedTextSettable=\(selectedSettable.boolValue) selectedTextError=\(selectedError.rawValue)")
        return settable.boolValue || selectedSettable.boolValue
    }
    func copyAndPaste(_ text: String, into target: Target?) async -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else { return refused("clipboard write failed") }
        // Wait for the command key from the toggle shortcut to be released.
        for _ in 0..<40 {
            if CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        guard !Task.isCancelled else { return refused("task cancelled") }
        guard let target else { return refused("no captured application") }
        guard let original = target.field else { return refused("no field captured at recording start") }
        guard let current = focusedField(target.pid) else { return refused("no focused field at delivery") }
        let secure = (attribute(current, kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole
        let trusted = AXIsProcessTrusted()
        let sameApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == target.pid
        let sameField = CFEqual(original, current)
        let isEditable = editable(current)
        diagnostic("delivery pid=\(target.pid) trusted=\(trusted) sameApp=\(sameApp) sameField=\(sameField) editable=\(isEditable) secure=\(secure)")
        guard DeliveryPolicy.canPaste(trusted: trusted, sameApp: sameApp,
                                      sameField: sameField, editable: isEditable, secure: secure) else {
            return refused("delivery policy rejected; see delivery flags")
        }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else {
            return refused("modifier keys still held after waiting")
        }
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return refused("keyboard event creation failed") }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        diagnostic("paste events posted; editor acceptance unverified")
        // Posting is a best-effort paste; text remains in the clipboard even if an editor rejects it.
        return true
    }
}
