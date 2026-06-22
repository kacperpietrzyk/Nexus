import Foundation
import Testing

@testable import NexusCore

@MainActor
@Suite("RefreshSuspensionCoordinator — ref-count + idempotent end + self-expiry")
struct RefreshSuspensionCoordinatorTests {

    /// Drivable clock + resume spy so the state machine is tested without real
    /// timers or sleeps.
    @MainActor
    private final class Harness {
        var now = Date(timeIntervalSince1970: 0)
        var resumeCount = 0

        func make(expiry: TimeInterval = 90) -> RefreshSuspensionCoordinator {
            RefreshSuspensionCoordinator(
                expiryInterval: expiry,
                clock: { self.now },
                onResume: { self.resumeCount += 1 }
            )
        }

        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    @Test("begin suspends; matching end resumes exactly once")
    func beginEndRoundTrip() {
        let h = Harness()
        let c = h.make()

        #expect(c.isSuspended == false)
        c.begin()
        #expect(c.isSuspended == true)
        #expect(h.resumeCount == 0)

        #expect(c.end() == true)
        #expect(c.isSuspended == false)
        #expect(h.resumeCount == 1)
    }

    @Test("end without a begin is a safe no-op (idempotent) — no spurious resume")
    func endWithoutBeginIsNoOp() {
        let h = Harness()
        let c = h.make()

        #expect(c.end() == false)
        #expect(c.end() == false)
        #expect(c.isSuspended == false)
        #expect(h.resumeCount == 0)
    }

    @Test("extra end after the batch closed does not double-resume")
    func extraEndDoesNotDoubleResume() {
        let h = Harness()
        let c = h.make()

        c.begin()
        #expect(c.end() == true)
        #expect(h.resumeCount == 1)

        #expect(c.end() == false)
        #expect(h.resumeCount == 1)
    }

    @Test("ref-count: nested begins stay suspended until the last end")
    func refCountNesting() {
        let h = Harness()
        let c = h.make()

        c.begin()
        c.begin()
        c.begin()
        #expect(c.isSuspended == true)

        #expect(c.end() == false)
        #expect(c.isSuspended == true)
        #expect(h.resumeCount == 0)

        #expect(c.end() == false)
        #expect(c.isSuspended == true)
        #expect(h.resumeCount == 0)

        #expect(c.end() == true)
        #expect(c.isSuspended == false)
        #expect(h.resumeCount == 1)
    }

    @Test("self-expiry: a dropped end auto-resumes once the deadline elapses")
    func selfExpiryResumes() {
        let h = Harness()
        let c = h.make(expiry: 90)

        c.begin()
        #expect(c.isSuspended == true)

        // Before the deadline: still suspended.
        h.advance(89)
        #expect(c.isSuspended == true)
        #expect(h.resumeCount == 0)

        // Past the deadline: lazily expires on the next read and resumes once.
        h.advance(2)
        #expect(c.isSuspended == false)
        #expect(h.resumeCount == 1)
    }

    @Test("explicit expireIfElapsed forces resume exactly once")
    func explicitExpiry() {
        let h = Harness()
        let c = h.make(expiry: 30)

        c.begin()
        h.advance(31)

        #expect(c.expireIfElapsed(now: h.now) == true)
        #expect(h.resumeCount == 1)
        // Idempotent: a second expiry call on a closed batch does nothing.
        #expect(c.expireIfElapsed(now: h.now) == false)
        #expect(h.resumeCount == 1)
    }

    @Test("begin re-arms (slides) the expiry deadline")
    func beginSlidesDeadline() {
        let h = Harness()
        let c = h.make(expiry: 90)

        c.begin()  // deadline = 90
        h.advance(80)
        c.begin()  // re-arms: deadline = 80 + 90 = 170; depth = 2

        // At t=160 (would have expired the FIRST deadline at 90) still suspended.
        h.advance(80)
        #expect(c.isSuspended == true)

        // One end drops depth 2 -> 1, still suspended, deadline intact.
        #expect(c.end() == false)
        #expect(c.isSuspended == true)

        // The other end resolves it.
        #expect(c.end() == true)
        #expect(h.resumeCount == 1)
    }

    @Test("end after expiry already fired is a no-op (no double resume)")
    func endAfterExpiryNoOp() {
        let h = Harness()
        let c = h.make(expiry: 30)

        c.begin()
        h.advance(31)
        #expect(c.isSuspended == false)  // triggers lazy expiry + resume
        #expect(h.resumeCount == 1)

        // The straggler end_batch that finally arrives must not resume again.
        #expect(c.end() == false)
        #expect(h.resumeCount == 1)
    }
}
