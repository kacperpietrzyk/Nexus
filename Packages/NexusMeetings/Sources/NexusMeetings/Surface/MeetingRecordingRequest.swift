import Foundation

public enum MeetingRecordingRequest {
    /// In-app request to start a manual recording via the system picker. Posted
    /// by UI entry points (menu bar, Meetings toolbar) on the local
    /// NotificationCenter; observed by the app composition root.
    public static let startManual = Notification.Name("nexus.startMeetingRecording")
}
