import Foundation
import Testing

@testable import NexusMeetings

@Test func debouncerAllowsFirstHitWithinWindow() {
    let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
    let debouncer = DetectionDebouncer(window: 60) { clock.value }
    #expect(debouncer.shouldEmit(fingerprint: "f1"))
}

@Test func canEmitDoesNotRecordUntilExplicitRecord() {
    let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
    let debouncer = DetectionDebouncer(window: 60) { clock.value }
    #expect(debouncer.canEmit(fingerprint: "f1"))
    #expect(debouncer.canEmit(fingerprint: "f1"))

    debouncer.recordEmit(fingerprint: "f1")

    #expect(debouncer.canEmit(fingerprint: "f1") == false)
}

@Test func debouncerBlocksSecondHitWithinWindow() {
    let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
    let debouncer = DetectionDebouncer(window: 60) { clock.value }
    _ = debouncer.shouldEmit(fingerprint: "f1")
    clock.value = clock.value.addingTimeInterval(30)
    #expect(debouncer.shouldEmit(fingerprint: "f1") == false)
}

@Test func debouncerAllowsHitAfterWindow() {
    let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
    let debouncer = DetectionDebouncer(window: 60) { clock.value }
    _ = debouncer.shouldEmit(fingerprint: "f1")
    clock.value = clock.value.addingTimeInterval(61)
    #expect(debouncer.shouldEmit(fingerprint: "f1"))
}

@Test func resetClearsFingerprint() {
    let clock = MutableClock(Date(timeIntervalSince1970: 1_000_000))
    let debouncer = DetectionDebouncer(window: 60) { clock.value }
    _ = debouncer.shouldEmit(fingerprint: "f1")
    debouncer.reset(fingerprint: "f1")
    #expect(debouncer.shouldEmit(fingerprint: "f1"))
}

private final class MutableClock: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
