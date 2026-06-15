import Foundation

/// Abstraction over the helper-process recording/processing control surface, so
/// the in-app Meetings UI (which lives in this package) can drive the helper
/// without importing the concrete `MeetingsHelperXPCClient` wiring that the host
/// app owns. The Mac app provides a concrete implementation backed by the XPC
/// client; tests/previews can supply a no-op.
///
/// Processing happens in the helper process (it owns the recordings and its own
/// `PipelineQueue`), so cancelling/re-processing a meeting is a cross-process
/// action that must go over XPC — an in-app `PipelineQueue` cannot reach the
/// helper's queue.
@MainActor
public protocol MeetingHelperControlling: AnyObject, Sendable {
    /// Cancel the helper's processing for a meeting (drops its queued job and
    /// cooperatively cancels it if currently running).
    func cancelProcessing(meetingID: UUID)
}
