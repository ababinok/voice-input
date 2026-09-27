import Foundation

public struct DictationSession {
    public enum Phase: Equatable { case idle, recording, transcribing, cancelling }
    public private(set) var phase: Phase = .idle
    public private(set) var id = UUID()
    public init() {}
    @discardableResult public mutating func start() -> UUID? {
        guard phase == .idle else { return nil }
        id = UUID(); phase = .recording
        return id
    }
    @discardableResult public mutating func stop() -> Bool {
        guard phase == .recording else { return false }
        phase = .transcribing; return true
    }
    public mutating func cancel() {
        if phase == .transcribing { phase = .cancelling }
        else { phase = .idle; id = UUID() }
    }
    public mutating func finish(_ token: UUID) -> Bool {
        guard token == id, phase == .transcribing || phase == .cancelling else { return false }
        let deliver = phase == .transcribing
        phase = .idle; id = UUID()
        return deliver
    }
    public mutating func fail() { phase = .idle; id = UUID() }
}

public enum DeliveryPolicy {
    public static func canPaste(trusted: Bool, sameApp: Bool, sameField: Bool, editable: Bool, secure: Bool) -> Bool {
        trusted && sameApp && sameField && editable && !secure
    }
}

/// A bounded acquisition at dictation start, never a retarget at delivery time.
public enum FocusCapture {
    @MainActor
    public static func retry<Element>(attempts: Int, isCurrent: () -> Bool,
                                      read: () -> Element?,
                                      wait: () async throws -> Void) async -> Element? {
        for _ in 0..<max(0, attempts) {
            guard !Task.isCancelled, isCurrent() else { return nil }
            do { try await wait() } catch { return nil }
            guard !Task.isCancelled, isCurrent() else { return nil }
            if let element = read() {
                return !Task.isCancelled && isCurrent() ? element : nil
            }
        }
        return nil
    }
}
