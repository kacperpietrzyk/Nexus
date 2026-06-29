import Foundation
import Testing

@testable import NexusMeetings

@Test func positivePIDTapsThatProcess() {
    #expect(CATapScope.resolve(pid: 1234) == .process(1234))
}

@Test func zeroPIDTapsGloballyForManualRecording() {
    #expect(CATapScope.resolve(pid: 0) == .global)
}

@Test func negativePIDFallsBackToGlobal() {
    #expect(CATapScope.resolve(pid: -1) == .global)
}
