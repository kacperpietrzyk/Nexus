import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("Cycles tools")
struct CyclesToolsTests {
    private static let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    private static let day: TimeInterval = 86_400

    @Test("cycles.list returns live cycles and honors the status filter")
    @MainActor
    func listCycles() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let cycles = CycleRepository(context: context.modelContext.context, now: { Self.stamp })
        let sprint = try cycles.create(
            name: "Sprint 12", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(14 * Self.day)
        )
        try cycles.setStatus(.active, on: sprint)
        _ = try cycles.create(
            name: "Sprint 13",
            startAt: Self.stamp.addingTimeInterval(14 * Self.day),
            endAt: Self.stamp.addingTimeInterval(28 * Self.day)
        )
        let deleted = try cycles.create(
            name: "Gone", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        try cycles.softDelete(deleted)

        let all = try await CyclesListTool().call(args: .object([:]), context: context)
        #expect(all["cycles"]?.arrayValue?.count == 2)

        let active = try await CyclesListTool().call(
            args: .object(["status": .string("active")]), context: context
        )
        let names = active["cycles"]?.arrayValue?.compactMap { $0["name"]?.stringValue }
        #expect(names == ["Sprint 12"])
        let statuses = active["cycles"]?.arrayValue?.compactMap { $0["status"]?.stringValue }
        #expect(statuses == ["active"])
    }

    @Test("cycles.list rejects an unknown status value")
    @MainActor
    func listRejectsBadStatus() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await CyclesListTool().call(
                args: .object(["status": .string("paused")]), context: context
            )
        }
    }

    @Test("cycles.assign_task assigns, clears, and reports cycle_id on the task DTO")
    @MainActor
    func assignTask() async throws {
        let task = TaskItem(title: "Build")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let cycles = CycleRepository(context: context.modelContext.context, now: { Self.stamp })
        let cycle = try cycles.create(
            name: "Sprint", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )

        let assigned = try await CyclesAssignTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "cycle_id": .string(cycle.id.uuidString),
            ]),
            context: context
        )
        #expect(task.cycleID == cycle.id)
        #expect(assigned["cycle_id"]?.stringValue == cycle.id.uuidString)

        _ = try await CyclesAssignTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "cycle_id": .null,
            ]),
            context: context
        )
        #expect(task.cycleID == nil)
    }

    @Test("cycles.assign_task rejects an unknown or deleted cycle")
    @MainActor
    func assignRejectsDeadCycle() async throws {
        let task = TaskItem(title: "Build")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let cycles = CycleRepository(context: context.modelContext.context, now: { Self.stamp })
        let dead = try cycles.create(
            name: "Dead", startAt: Self.stamp, endAt: Self.stamp.addingTimeInterval(Self.day)
        )
        try cycles.softDelete(dead)

        await #expect(throws: AgentError.self) {
            _ = try await CyclesAssignTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "cycle_id": .string(dead.id.uuidString),
                ]),
                context: context
            )
        }
        #expect(task.cycleID == nil)
    }

    @Test("cycles tools are registered in CoreTaskTools")
    func registered() {
        let names = CoreTaskTools.all().map(\.name)
        #expect(names.contains("cycles.list"))
        #expect(names.contains("cycles.assign_task"))
    }
}
