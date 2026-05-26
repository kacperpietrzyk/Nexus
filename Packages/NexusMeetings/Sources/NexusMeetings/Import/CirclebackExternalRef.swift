import Foundation

public enum CirclebackExternalRef {
    public static let meetingPrefix = "circleback:meeting:"
    public static let actionItemPrefix = "circleback:actionItem:"

    public static func meeting(id: Int) -> String { "\(meetingPrefix)\(id)" }
    public static func actionItem(id: Int) -> String { "\(actionItemPrefix)\(id)" }
}
