import Foundation

/// Repository-level notification hook. Defined in NexusCore so the
/// repository can dispatch without importing UserNotifications.
/// TasksFeature provides the production conformance (NotificationScheduler).
///
/// All methods are `@MainActor` because conformers operate on
/// `TaskItem` (a SwiftData `@Model` bound to a MainActor `ModelContext`).
@MainActor
public protocol NotificationScheduling: Sendable {
    func schedule(_ task: TaskItem) async throws
    func cancel(taskID: UUID) async
    func reschedule(_ task: TaskItem) async throws
    func scheduleSnooze(_ task: TaskItem, until: Date) async throws
}

public struct NoopNotificationScheduler: NotificationScheduling {
    public init() {}
    public func schedule(_: TaskItem) async throws {}
    public func cancel(taskID _: UUID) async {}
    public func reschedule(_: TaskItem) async throws {}
    public func scheduleSnooze(_: TaskItem, until _: Date) async throws {}
}
