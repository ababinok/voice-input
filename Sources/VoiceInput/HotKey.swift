import AppKit
import Carbon

@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?

    func register() throws {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let instance = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { instance.onPress?() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw AppError.message("Не удалось подключить горячую клавишу (\(status)).") }
        // ANSI grave is the physical key, independent of the input language.
        let result = RegisterEventHotKey(UInt32(kVK_ANSI_Grave), UInt32(cmdKey), EventHotKeyID(signature: 0x564F4943, id: 1), GetApplicationEventTarget(), 0, &reference)
        guard result == noErr else {
            throw AppError.message("Сочетание ⌘ + ` занято или недоступно (\(result)). Освободите его в настройках клавиатуры и перезапустите Voice Input.")
        }
    }
    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
