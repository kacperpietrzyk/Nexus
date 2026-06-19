// Packages/TasksFeature/Sources/TasksFeature/Inbox/UnscheduledBridgeProjector.swift
import Foundation
import InboxShell

/// Single "go triage your unscheduled tasks" bridge card. Count is injected so
/// the projector stays testable; the composition root supplies the real
/// `TodayQuery().noDate()` fetchCount (see `TasksNoDateSource.count()`).
public struct UnscheduledBridgeProjector: FeedProjector {
    public let stream: FeedStream = .bridge
    private let countProvider: @Sendable () async -> Int

    public init(countProvider: @escaping @Sendable () async -> Int) {
        self.countProvider = countProvider
    }

    public func project() async throws -> [FeedItem] {
        let count = await countProvider()
        guard count > 0 else { return [] }
        return [
            FeedItem(
                key: "bridge:unscheduled",
                stream: .bridge,
                title: "\(count) unscheduled tasks",
                subtitle: "Triage in Tasks",
                createdAt: .distantFuture,  // pin to top of the All list
                route: .unscheduledTasks,
                iconName: "tray.full"
            )
        ]
    }
}
