import Foundation

/// `DistributedNotificationCenter` names for app↔helper readiness coordination.
/// App→helper: `requestPermissions`, `downloadModels`, `refreshReadiness`.
/// Helper→app: `readinessDidChange` (posted after a fresh snapshot is written).
public enum MeetingsReadinessNotification {
    public static let requestPermissions = Notification.Name(
        "com.kacperpietrzyk.nexus.meetings.requestPermissions"
    )
    public static let downloadModels = Notification.Name(
        "com.kacperpietrzyk.nexus.meetings.downloadModels"
    )
    public static let refreshReadiness = Notification.Name(
        "com.kacperpietrzyk.nexus.meetings.refreshReadiness"
    )
    public static let readinessDidChange = Notification.Name(
        "com.kacperpietrzyk.nexus.meetings.readinessDidChange"
    )
}
