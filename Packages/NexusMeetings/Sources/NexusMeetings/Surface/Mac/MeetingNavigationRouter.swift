import Combine
import Foundation

@MainActor
public final class MeetingNavigationRouter: ObservableObject {
    @Published public var selectedMeetingID: UUID?

    public let selections: AsyncStream<UUID>

    private let continuation: AsyncStream<UUID>.Continuation

    public init() {
        let stream = AsyncStream<UUID>.makeStream(of: UUID.self)
        selections = stream.stream
        continuation = stream.continuation
    }

    public func navigate(to meetingID: UUID) {
        selectedMeetingID = meetingID
        continuation.yield(meetingID)
    }
}
