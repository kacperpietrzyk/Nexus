import Foundation

/// Wire-format constants for the Watch to iPhone bridge.
public enum WatchPayload {
    public static let typeKey = "type"
    public static let inputKey = "input"
    public static let promptKey = "prompt"
    public static let idKey = "id"
    public static let taskIDKey = "taskID"
    public static let snoozeUntilKey = "until"
    public static let snapshotPayloadKey = "payload"

    public static let captureType = "capture"
    public static let askNexusType = "ask-nexus"
    public static let markDoneType = "mark-done"
    public static let reopenType = "reopen"
    public static let reloadComplicationsType = "reload-complications"
    public static let notifSnapshotType = "notif-snapshot"
    public static let snoozeActionType = "snooze-action"
}
