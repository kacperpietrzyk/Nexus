import Foundation

public struct MeetingDetectionEvent: Sendable, Equatable {
    public let fingerprint: String
    public let bundleID: String
    public let pid: Int32?
    public let suggestedTitle: String
    public let detectedAt: Date
    public let calendarEventID: String?

    public init(
        fingerprint: String,
        bundleID: String,
        pid: Int32? = nil,
        suggestedTitle: String,
        detectedAt: Date,
        calendarEventID: String? = nil
    ) {
        self.fingerprint = fingerprint
        self.bundleID = bundleID
        self.pid = pid
        self.suggestedTitle = suggestedTitle
        self.detectedAt = detectedAt
        self.calendarEventID = calendarEventID
    }
}
