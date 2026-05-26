import Foundation

public protocol AgentScheduler: Sendable {
    func start() async
    func reschedule(_ scheduleID: UUID) async
    func suspend(_ scheduleID: UUID) async
    func suspendAll() async
}

public struct AgentSchedulerNoop: AgentScheduler {
    public init() {}
    public func start() async {}
    public func reschedule(_ scheduleID: UUID) async {}
    public func suspend(_ scheduleID: UUID) async {}
    public func suspendAll() async {}
}
