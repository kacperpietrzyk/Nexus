import Foundation
import Testing

@testable import NexusMeetings

@Test func storageDefaults() throws {
    let meetingID = UUID()
    let url = URL(fileURLWithPath: "/tmp/\(meetingID.uuidString)")
    let storage = MeetingAudioStorage(
        meetingID: meetingID,
        folderURL: url,
        retentionPolicy: .days30
    )
    #expect(storage.meetingID == meetingID)
    #expect(storage.retentionPolicy == "30d")
    #expect(storage.hasAudio == true)
    #expect(storage.totalBytes == 0)
    let delta = storage.expiresAt!.timeIntervalSince(storage.createdAt)
    #expect(abs(delta - 30 * 86_400) < 1.0)
}

@Test func storageForeverRetentionHasNoExpiry() {
    let storage = MeetingAudioStorage(
        meetingID: UUID(),
        folderURL: URL(fileURLWithPath: "/tmp/x"),
        retentionPolicy: .forever
    )
    #expect(storage.expiresAt == nil)
}

@Test func storageNeverRetentionExpiresImmediately() {
    let storage = MeetingAudioStorage(
        meetingID: UUID(),
        folderURL: URL(fileURLWithPath: "/tmp/x"),
        retentionPolicy: .never
    )
    #expect(storage.expiresAt != nil)
    #expect(storage.expiresAt! <= Date())
}
