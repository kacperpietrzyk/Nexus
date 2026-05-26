import Foundation
import Testing
@testable import NexusMeetings

@Test func meetingExternalSourceIDFormat() {
    #expect(CirclebackExternalRef.meeting(id: 8_771_435) == "circleback:meeting:8771435")
}

@Test func actionItemExternalSourceIDFormat() {
    #expect(CirclebackExternalRef.actionItem(id: 17_752_891) == "circleback:actionItem:17752891")
}

@Test func meetingPrefixHelperMatchesSourcePattern() {
    #expect(CirclebackExternalRef.meetingPrefix == "circleback:meeting:")
    #expect(CirclebackExternalRef.actionItemPrefix == "circleback:actionItem:")
}
