import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("TasksMergeTool")
struct TasksMergeToolTests {

    // MARK: - tasks.merge: happy path

    @MainActor
    @Test("merge repoints edges, unions tags, and soft-deletes the duplicate")
    func mergeRepointsTagsAndSoftDeletes() async throws {
        let survivor = TaskItem(title: "Buy groceries", tags: ["shopping"])
        let duplicate = TaskItem(title: "Buy groceries (dup)", tags: ["errands", "shopping"])
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        // Link something → duplicate (incoming edge).
        let noteID = UUID()
        try fixture.context.linkRepository.findOrCreate(
            from: (.note, noteID),
            to: (.task, duplicate.id),
            linkKind: .mentions
        )

        let result = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        // Returns the surviving task DTO.
        let dto = try TasksToolJSON.decode(TaskDTO.self, from: result)
        #expect(dto.id == survivor.id.uuidString)

        // Tags are unioned (deduped, lowercase).
        #expect(Set(survivor.tags) == Set(["shopping", "errands"]))

        // The duplicate's incoming edge now points at the survivor.
        let survivorLinks = try fixture.context.linkRepository.backlinks(to: (.task, survivor.id))
        #expect(survivorLinks.count == 1)
        #expect(survivorLinks.first?.fromID == noteID)

        // The duplicate is soft-deleted.
        let allTasks = try fixture.context.modelContext.context.fetch(FetchDescriptor<TaskItem>())
        let dupRow = allTasks.first { $0.id == duplicate.id }
        #expect(dupRow?.deletedAt != nil)

        // Survivor is still live.
        #expect(survivor.deletedAt == nil)
    }

    // MARK: - tasks.merge: fill-empty fields

    @MainActor
    @Test("merge fills empty survivor fields and does not overwrite set survivor fields")
    func mergeFillsEmptyFields() async throws {
        let dueDate = Date(timeIntervalSince1970: 1_700_100_000)
        let survivorDue = Date(timeIntervalSince1970: 1_800_000_000)
        let survivor = TaskItem(title: "Task A", dueAt: survivorDue)
        let duplicate = TaskItem(title: "Task B", dueAt: dueDate, tags: ["work"])
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        // Survivor's already-set dueAt must NOT be overwritten by the duplicate's.
        #expect(survivor.dueAt == survivorDue)
        // Tags unioned (duplicate's tag appears on survivor).
        #expect(survivor.tags.contains("work"))
    }

    // MARK: - tasks.merge: earlier createdAt wins

    @MainActor
    @Test("merge carries the earlier createdAt")
    func mergeCarriesEarlierCreatedAt() async throws {
        let earlier = Date(timeIntervalSince1970: 1_600_000_000)
        let later = Date(timeIntervalSince1970: 1_700_000_000)

        let survivor = TaskItem(title: "Survivor")
        let duplicate = TaskItem(title: "Duplicate")

        // Manually set createdAt so survivor is newer.
        survivor.createdAt = later
        duplicate.createdAt = earlier

        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        #expect(survivor.createdAt == earlier)
    }

    // MARK: - tasks.merge: survivor's older createdAt is not overwritten

    @MainActor
    @Test("merge keeps survivor createdAt when it is already earlier")
    func mergeSurvivorCreatedAtNotOverwritten() async throws {
        let earlier = Date(timeIntervalSince1970: 1_600_000_000)
        let later = Date(timeIntervalSince1970: 1_700_000_000)

        let survivor = TaskItem(title: "Survivor")
        let duplicate = TaskItem(title: "Duplicate")

        survivor.createdAt = earlier
        duplicate.createdAt = later

        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        #expect(survivor.createdAt == earlier)
    }

    // MARK: - tasks.merge: atomicity / self-merge guard

    @MainActor
    @Test("merge rejects merging a task into itself, leaving the task untouched")
    func mergeRejectsSelf() async throws {
        let task = TaskItem(title: "Solo task")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksMergeTool().call(
                args: .object([
                    "into_id": .string(task.id.uuidString),
                    "from_id": .string(task.id.uuidString),
                ]),
                context: fixture.context
            )
        }

        // Atomicity: guard throws before any mutation — task must be live.
        #expect(task.deletedAt == nil)
        let all = try fixture.context.modelContext.context.fetch(FetchDescriptor<TaskItem>())
        #expect(all.contains { $0.id == task.id })
    }

    // MARK: - tasks.merge: already-deleted source

    @MainActor
    @Test("merge rejects already-deleted from_id")
    func mergeRejectsAlreadyDeleted() async throws {
        let survivor = TaskItem(title: "Survivor")
        let tombstone = TaskItem(title: "Tombstone")
        tombstone.deletedAt = Date()
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, tombstone])

        // `liveTask` throws .notFound for soft-deleted tasks.
        await #expect(throws: AgentError.self) {
            _ = try await TasksMergeTool().call(
                args: .object([
                    "into_id": .string(survivor.id.uuidString),
                    "from_id": .string(tombstone.id.uuidString),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - tasks.merge: duration paired carry (Fix 1)

    @MainActor
    @Test("merge carries both estimatedDurationSeconds and durationSourceRaw when survivor has no estimate")
    func mergeFillsDurationPaired() async throws {
        let survivor = TaskItem(title: "Survivor")
        // survivor has NO duration or source
        let duplicate = TaskItem(
            title: "Duplicate",
            estimatedDurationSeconds: 3600,
            durationSource: .explicit
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        // Both value AND source must arrive together.
        #expect(survivor.estimatedDurationSeconds == 3600)
        #expect(survivor.durationSourceRaw == DurationSource.explicit.rawValue)
    }

    @MainActor
    @Test("merge does not overwrite survivor duration or source when survivor already has an estimate")
    func mergeDurationNotOverwrittenWhenSurvivorHasEstimate() async throws {
        let survivor = TaskItem(
            title: "Survivor",
            estimatedDurationSeconds: 1800,
            durationSource: .explicit
        )
        let duplicate = TaskItem(
            title: "Duplicate",
            estimatedDurationSeconds: 7200,
            durationSource: .estimated
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        // Survivor's existing value+source must NOT be overwritten.
        #expect(survivor.estimatedDurationSeconds == 1800)
        #expect(survivor.durationSourceRaw == DurationSource.explicit.rawValue)
    }

    // MARK: - tasks.merge: nilable scalar fill — cycleID and assignedAgent (Fix 2)

    @MainActor
    @Test("merge fills cycleID and assignedAgent when survivor fields are nil")
    func mergeFillsCycleAndAgent() async throws {
        let cycleID = UUID()
        let survivor = TaskItem(title: "Survivor")
        let duplicate = TaskItem(
            title: "Duplicate",
            assignedAgent: .codex,
            cycleID: cycleID
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        #expect(survivor.cycleID == cycleID)
        #expect(survivor.assignedAgent == AgentAssignee.codex.rawValue)
    }

    @MainActor
    @Test("merge does not overwrite survivor cycleID or assignedAgent when already set")
    func mergeCycleAndAgentNotOverwritten() async throws {
        let survivorCycle = UUID()
        let loserCycle = UUID()
        let survivor = TaskItem(
            title: "Survivor",
            assignedAgent: .claude,
            cycleID: survivorCycle
        )
        let duplicate = TaskItem(
            title: "Duplicate",
            assignedAgent: .codex,
            cycleID: loserCycle
        )
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        #expect(survivor.cycleID == survivorCycle)
        #expect(survivor.assignedAgent == AgentAssignee.claude.rawValue)
    }

    // MARK: - tasks.merge: occurredAt carry (whole-branch fix)

    @MainActor
    @Test("merge carries loser's occurredAt when survivor has none")
    func mergeCarriesOccurredAt() async throws {
        let eventDate = Date(timeIntervalSince1970: 1_650_000_000)
        let survivor = TaskItem(title: "Survivor")
        // survivor has NO occurredAt
        let duplicate = TaskItem(title: "Duplicate")
        duplicate.occurredAt = eventDate
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        #expect(survivor.occurredAt == eventDate)
    }

    @MainActor
    @Test("merge does not overwrite survivor occurredAt when already set")
    func mergeSurvivorOccurredAtNotOverwritten() async throws {
        let survivorDate = Date(timeIntervalSince1970: 1_700_000_000)
        let loserDate = Date(timeIntervalSince1970: 1_600_000_000)
        let survivor = TaskItem(title: "Survivor")
        survivor.occurredAt = survivorDate
        let duplicate = TaskItem(title: "Duplicate")
        duplicate.occurredAt = loserDate
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        // Survivor's existing occurredAt must NOT be overwritten.
        #expect(survivor.occurredAt == survivorDate)
    }

    // MARK: - tasks.merge: subtask re-parenting (Fix 3)

    @MainActor
    @Test("merge detaches loser's subtasks to root and keeps them live")
    func mergeReparentsSubtasks() async throws {
        let survivor = TaskItem(title: "Survivor")
        let loser = TaskItem(title: "Loser")
        let child = TaskItem(title: "Child subtask")
        child.parentTaskID = loser.id
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, loser, child])

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(loser.id.uuidString),
            ]),
            context: fixture.context
        )

        // Loser is soft-deleted.
        #expect(loser.deletedAt != nil)

        // Child is still live (not cascade-deleted).
        #expect(child.deletedAt == nil)

        // Child's parent pointer is cleared to root — no longer points at the tombstone.
        #expect(child.parentTaskID == nil)
    }

    // MARK: - tasks.merge: duplicate edge dedup

    @MainActor
    @Test("merge deduplicates edges already on the survivor")
    func mergeDedupesEdges() async throws {
        let survivor = TaskItem(title: "Survivor")
        let duplicate = TaskItem(title: "Duplicate")
        let fixture = try await InMemoryAgentContext.make(tasks: [survivor, duplicate])

        let noteID = UUID()
        // Same note→task edge already on both: should end up as ONE edge on survivor.
        try fixture.context.linkRepository.findOrCreate(
            from: (.note, noteID),
            to: (.task, survivor.id),
            linkKind: .mentions
        )
        try fixture.context.linkRepository.findOrCreate(
            from: (.note, noteID),
            to: (.task, duplicate.id),
            linkKind: .mentions
        )

        _ = try await TasksMergeTool().call(
            args: .object([
                "into_id": .string(survivor.id.uuidString),
                "from_id": .string(duplicate.id.uuidString),
            ]),
            context: fixture.context
        )

        let survivorLinks = try fixture.context.linkRepository.backlinks(to: (.task, survivor.id))
        #expect(survivorLinks.count == 1)
    }
}
