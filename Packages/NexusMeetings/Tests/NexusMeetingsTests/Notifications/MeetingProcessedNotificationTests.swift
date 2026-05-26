import Foundation
import Testing

@testable import NexusMeetings

@Test func processedNotificationBuildsBodyWithCounts() {
    let note = MeetingProcessedNotification.make(
        title: "Daily standup",
        autoCount: 3,
        lowConfidenceCount: 1
    )
    #expect(note.title.contains("Daily standup"))
    #expect(note.body.contains("3 action items"))
    #expect(note.body.contains("1"))
}

@Test func processedNotificationBuildsSingularBodyWithoutLowConfidence() {
    let note = MeetingProcessedNotification.make(
        title: "Design review",
        autoCount: 1,
        lowConfidenceCount: 0
    )
    #expect(note.title == "\"Design review\" processed")
    #expect(note.body == "1 action item extracted. Tap to review.")
}

@Test func processedNotificationBuildsZeroBodyWithoutLowConfidence() {
    let note = MeetingProcessedNotification.make(
        title: "Retro",
        autoCount: 0,
        lowConfidenceCount: 0
    )
    #expect(note.title == "\"Retro\" processed")
    #expect(note.body == "0 action items extracted. Tap to review.")
}
