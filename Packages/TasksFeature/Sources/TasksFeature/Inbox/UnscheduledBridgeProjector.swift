// Packages/TasksFeature/Sources/TasksFeature/Inbox/UnscheduledBridgeProjector.swift
import Foundation
import InboxShell
import NexusCore
import SwiftData

/// Cheap COUNT path for the unscheduled-tasks bridge card — a `fetchCount` over
/// the no-date inbox window (no materialization). Lifted verbatim from the
/// deleted `TasksNoDateSource.count()` so the composition root can inject it
/// into `UnscheduledBridgeProjector` without TasksFeature re-importing the old
/// inbox-source machinery. `@MainActor` to match the SwiftData isolation the
/// rest of the repositories use.
@MainActor
public struct TasksNoDateInboxCount {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func count() throws -> Int {
        try TodayQuery().noDateInboxWindow().count(in: context)
    }
}

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
