import Foundation

@main
struct SessionTests {
    static func main() {
        var checks = 0
        func expect(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError("FAIL: \(message)") }
            checks += 1
        }
        var session = DictationSession()
        let first = session.start()!
        expect(session.start() == nil, "duplicate start")
        expect(session.stop(), "stop recording")
        expect(!session.stop(), "duplicate stop")
        expect(session.start() == nil, "start during inference")
        expect(session.finish(first), "deliver result")
        expect(!session.finish(first), "do not deliver twice")
        expect(session.phase == .idle, "return to idle")

        let cancelled = session.start()!
        session.stop(); session.cancel()
        expect(session.phase == .cancelling, "cancelling state")
        expect(session.start() == nil, "wait for cancelled inference")
        expect(!session.finish(cancelled), "discard cancelled result")
        expect(session.phase == .idle, "cancel completion")

        let old = session.start()!
        session.cancel()
        let current = session.start()!
        session.stop()
        expect(!session.finish(old), "discard stale result")
        expect(session.phase == .transcribing, "stale result does not reset current session")
        session.fail()
        expect(!session.finish(current), "failure invalidates session")
        expect(session.phase == .idle, "failure recovers")

        expect(DeliveryPolicy.canPaste(trusted: true, sameApp: true, sameField: true, editable: true, secure: false), "valid paste")
        for failure in 0..<5 {
            expect(!DeliveryPolicy.canPaste(trusted: failure != 0, sameApp: failure != 1,
                                           sameField: failure != 2, editable: failure != 3, secure: failure == 4), "unsafe paste \(failure)")
        }
        print("PASS: \(checks) lifecycle and paste-policy checks")
    }
}
