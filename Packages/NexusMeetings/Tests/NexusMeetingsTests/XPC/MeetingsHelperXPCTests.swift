import Foundation
import Testing

@testable import NexusMeetings

@Suite("Meetings helper XPC")
struct MeetingsHelperXPCTests {
    @Test func meetingHandlePayloadRoundTripsWithSecureCoding() throws {
        let meetingID = UUID()
        let payload = MeetingHandlePayload(
            meetingID: meetingID,
            folderPath: "/tmp/NexusMeetings/\(meetingID.uuidString)"
        )

        let decoded = try roundTrip(payload, as: MeetingHandlePayload.self)

        #expect(decoded.meetingID == meetingID)
        #expect(decoded.folderPath == "/tmp/NexusMeetings/\(meetingID.uuidString)")
    }

    @Test func recordingStateSnapshotRoundTripsWithSecureCoding() throws {
        let meetingID = UUID()
        let snapshot = RecordingStateSnapshot(
            isRecording: true,
            meetingID: meetingID,
            elapsedSec: 92,
            micLevel: 0.42,
            othersLevel: 0.85
        )

        let decoded = try roundTrip(snapshot, as: RecordingStateSnapshot.self)

        #expect(decoded.isRecording)
        #expect(decoded.meetingID == meetingID)
        #expect(decoded.elapsedSec == 92)
        #expect(decoded.micLevel == 0.42)
        #expect(decoded.othersLevel == 0.85)
    }

    @Test func recordingStateSnapshotAllowsMissingMeetingID() throws {
        let snapshot = RecordingStateSnapshot(
            isRecording: false,
            meetingID: nil,
            elapsedSec: 0,
            micLevel: 0,
            othersLevel: 0
        )

        let decoded = try roundTrip(snapshot, as: RecordingStateSnapshot.self)

        #expect(decoded.isRecording == false)
        #expect(decoded.meetingID == nil)
    }

    #if os(macOS)
    @Test func xpcClientPublishesStableMachServiceName() {
        #expect(MeetingsHelperXPCClient.machServiceName == "com.kacperpietrzyk.nexus.meetings-helper")
    }

    @Test func xpcClientProxyCreationDoesNotRequireRunningHelper() {
        let client = MeetingsHelperXPCClient()
        _ = client.connect()
        client.disconnect()
    }
    #endif

    private func roundTrip<T: NSObject & NSSecureCoding>(_ value: T, as type: T.Type) throws -> T {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: value,
            requiringSecureCoding: true
        )
        let decoded = try NSKeyedUnarchiver.unarchivedObject(ofClass: type, from: data)
        return try #require(decoded)
    }
}
