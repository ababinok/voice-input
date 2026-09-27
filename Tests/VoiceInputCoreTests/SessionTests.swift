import Foundation

@main
struct SessionTests {
    @MainActor static func main() async {
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
        var reads = 0
        let delayed = await FocusCapture.retry(attempts: 25, isCurrent: { true }, read: {
            reads += 1
            return reads == 21 ? "original field" : nil
        }, wait: {})
        expect(delayed == "original field" && reads == 21, "capture renderer focus after delayed accessibility activation")

        reads = 0
        let missing: String? = await FocusCapture.retry(attempts: 25, isCurrent: { true }, read: {
            reads += 1; return nil
        }, wait: {})
        expect(missing == nil && reads == 25, "missing focus has a bounded retry budget")

        reads = 0
        let alreadyChanged = await FocusCapture.retry(attempts: 25, isCurrent: { false }, read: {
            reads += 1; return "other field"
        }, wait: {})
        expect(alreadyChanged == nil && reads == 0, "never read a different app or window")

        var sameContext = true
        let changedDuringWait = await FocusCapture.retry(attempts: 25, isCurrent: { sameContext }, read: {
            reads += 1; return "other field"
        }, wait: { sameContext = false })
        expect(changedDuringWait == nil && reads == 0, "reject context changed while awaiting accessibility")

        sameContext = true
        let changedDuringRead = await FocusCapture.retry(attempts: 25, isCurrent: { sameContext }, read: {
            sameContext = false; return "stale field"
        }, wait: {})
        expect(changedDuringRead == nil, "revalidate context after AX read")

        reads = 0
        let interrupted = await FocusCapture.retry(attempts: 25, isCurrent: { true }, read: {
            reads += 1; return "field"
        }, wait: { throw CancellationError() })
        expect(interrupted == nil && reads == 0, "cancel acquisition during wait")

        let acquisition = Task { @MainActor in
            await FocusCapture.retry(attempts: 25, isCurrent: { true }, read: {
                reads += 1; return "field"
            }, wait: { await Task.yield() })
        }
        acquisition.cancel()
        let cancelledCapture = await acquisition.value
        expect(cancelledCapture == nil && reads == 0, "cancelled acquisition cannot capture a new target")
        print("PASS: \(checks) lifecycle, paste-policy and focus-capture checks")
    }
}
