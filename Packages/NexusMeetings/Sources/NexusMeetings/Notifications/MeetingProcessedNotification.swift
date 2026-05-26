import Foundation

public struct MeetingProcessedNotification: Sendable, Equatable {
    public let title: String
    public let body: String

    public static func make(
        title: String,
        autoCount: Int,
        lowConfidenceCount: Int
    ) -> MeetingProcessedNotification {
        let extras =
            if lowConfidenceCount > 0 {
                " (\(lowConfidenceCount) low-confidence to review)"
            } else {
                ""
            }
        let plural = autoCount == 1 ? "action item" : "action items"
        return .init(
            title: "\"\(title)\" processed",
            body: "\(autoCount) \(plural) extracted\(extras). Tap to review."
        )
    }
}
