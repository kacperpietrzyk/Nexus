import Foundation

public enum MeetingSummaryHandoffNotification {
    /// Helper → app: a meeting is transcribed and waiting for the assistant
    /// model to summarize it. userInfo: ["meetingID": String, "folderPath": String].
    public static let needsExternalSummary = Notification.Name(
        "com.kacperpietrzyk.nexus.meetings.needsExternalSummary"
    )

    public static func post(meetingID: UUID, folderPath: String) {
        DistributedNotificationCenter.default().postNotificationName(
            needsExternalSummary,
            object: nil,
            userInfo: ["meetingID": meetingID.uuidString, "folderPath": folderPath],
            deliverImmediately: true
        )
    }

    public static func parse(_ note: Notification) -> (id: UUID, folder: URL)? {
        guard
            let idString = note.userInfo?["meetingID"] as? String,
            let id = UUID(uuidString: idString),
            let path = note.userInfo?["folderPath"] as? String
        else { return nil }
        return (id, URL(fileURLWithPath: path))
    }
}
