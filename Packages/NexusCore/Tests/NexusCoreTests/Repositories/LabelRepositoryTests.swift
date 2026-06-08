import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("LabelRepository")
struct LabelRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Label.self, Link.self, TaskItem.self, Project.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @MainActor
    private func makeRepo() throws -> (LabelRepository, ModelContext) {
        let context = try makeContext()
        return (LabelRepository(context: context, now: { .now }), context)
    }

    // MARK: - CRUD

    @MainActor
    @Test("create persists a label and find resolves it")
    func createAndFind() throws {
        let (repo, _) = try makeRepo()
        let label = try repo.create(name: "feature", glyphKey: "sparkles", group: .domain)
        #expect(try repo.find(id: label.id)?.name == "feature")
        #expect(try repo.allActive().count == 1)
    }

    @MainActor
    @Test("softDelete hides a label from allActive and labels(for:)")
    func softDeleteHidesLabel() throws {
        let (repo, _) = try makeRepo()
        let label = try repo.create(name: "temp", group: .free)
        let taskID = UUID()
        try repo.assign(label, to: (.task, taskID))
        #expect(try repo.labels(for: (.task, taskID)).count == 1)

        try repo.softDelete(label)
        #expect(try repo.allActive().isEmpty)
        // The edge survives but resolves to a soft-deleted label, so it's filtered out.
        #expect(try repo.labels(for: (.task, taskID)).isEmpty)
    }

    // MARK: - Single-select (I5)

    @MainActor
    @Test("assigning a second domain label replaces the first on a task (I5)")
    func domainSingleSelectOnTask() throws {
        let (repo, _) = try makeRepo()
        let feature = try repo.create(name: "feature", group: .domain)
        let bug = try repo.create(name: "bug", group: .domain)
        let taskID = UUID()

        try repo.assign(feature, to: (.task, taskID))
        try repo.assign(bug, to: (.task, taskID))

        let labels = try repo.labels(for: (.task, taskID))
        #expect(labels.map(\.name) == ["bug"])
    }

    @MainActor
    @Test("assigning a second gate label replaces the first on a project (I5)")
    func gateSingleSelectOnProject() throws {
        let (repo, _) = try makeRepo()
        let needs = try repo.create(name: "needsDecision", group: .gate)
        let decided = try repo.create(name: "decided", group: .gate)
        let projectID = UUID()

        try repo.assign(needs, to: (.project, projectID))
        try repo.assign(decided, to: (.project, projectID))

        let labels = try repo.labels(for: (.project, projectID))
        #expect(labels.map(\.name) == ["decided"])
    }

    @MainActor
    @Test("free labels accumulate (I5)")
    func freeLabelsAccumulate() throws {
        let (repo, _) = try makeRepo()
        let urgent = try repo.create(name: "urgent", group: .free)
        let blocked = try repo.create(name: "blocked", group: .free)
        let taskID = UUID()

        try repo.assign(urgent, to: (.task, taskID))
        try repo.assign(blocked, to: (.task, taskID))

        #expect(Set(try repo.labels(for: (.task, taskID)).map(\.name)) == ["urgent", "blocked"])
    }

    @MainActor
    @Test("single-select across groups is independent: a domain swap leaves gate + free intact")
    func crossGroupIndependence() throws {
        let (repo, _) = try makeRepo()
        let feature = try repo.create(name: "feature", group: .domain)
        let bug = try repo.create(name: "bug", group: .domain)
        let needs = try repo.create(name: "needsDecision", group: .gate)
        let urgent = try repo.create(name: "urgent", group: .free)
        let taskID = UUID()

        try repo.assign(feature, to: (.task, taskID))
        try repo.assign(needs, to: (.task, taskID))
        try repo.assign(urgent, to: (.task, taskID))
        try repo.assign(bug, to: (.task, taskID))  // replaces feature only

        #expect(Set(try repo.labels(for: (.task, taskID)).map(\.name)) == ["bug", "needsDecision", "urgent"])
    }

    @MainActor
    @Test("single-select does not touch the same label on a different endpoint")
    func singleSelectScopedToEndpoint() throws {
        let (repo, _) = try makeRepo()
        let feature = try repo.create(name: "feature", group: .domain)
        let bug = try repo.create(name: "bug", group: .domain)
        let taskA = UUID()
        let taskB = UUID()

        try repo.assign(feature, to: (.task, taskA))
        try repo.assign(feature, to: (.task, taskB))
        try repo.assign(bug, to: (.task, taskA))  // swaps A only

        #expect(try repo.labels(for: (.task, taskA)).map(\.name) == ["bug"])
        #expect(try repo.labels(for: (.task, taskB)).map(\.name) == ["feature"])
    }

    @MainActor
    @Test("re-assigning the same label is idempotent (no duplicate edge)")
    func assignIsIdempotent() throws {
        let (repo, context) = try makeRepo()
        let feature = try repo.create(name: "feature", group: .domain)
        let taskID = UUID()
        try repo.assign(feature, to: (.task, taskID))
        try repo.assign(feature, to: (.task, taskID))

        #expect(try repo.labels(for: (.task, taskID)).count == 1)
        let edges = try context.fetch(FetchDescriptor<Link>()).filter { $0.linkKind == .labeled }
        #expect(edges.count == 1)
    }

    @MainActor
    @Test("remove deletes the edge but keeps the shared label row")
    func removeKeepsLabelRow() throws {
        let (repo, _) = try makeRepo()
        let feature = try repo.create(name: "feature", group: .domain)
        let taskID = UUID()
        try repo.assign(feature, to: (.task, taskID))
        try repo.remove(feature, from: (.task, taskID))

        #expect(try repo.labels(for: (.task, taskID)).isEmpty)
        #expect(try repo.find(id: feature.id)?.deletedAt == nil)
    }

    @MainActor
    @Test("single-select deletes only the edge, never the shared label row")
    func singleSelectDeletesEdgeNotRow() throws {
        let (repo, _) = try makeRepo()
        let feature = try repo.create(name: "feature", group: .domain)
        let bug = try repo.create(name: "bug", group: .domain)
        let taskID = UUID()
        try repo.assign(feature, to: (.task, taskID))
        try repo.assign(bug, to: (.task, taskID))

        // feature is no longer on the task but still exists as a reusable row.
        #expect(try repo.find(id: feature.id)?.deletedAt == nil)
        #expect(try repo.allActive().count == 2)
    }

    // MARK: - Seed

    @MainActor
    @Test("seedSystemLabels creates all system labels with isSystem=true")
    func seedCreatesSystemLabels() throws {
        let (repo, _) = try makeRepo()
        try repo.seedSystemLabels()
        let all = try repo.allActive()
        #expect(all.count == SystemLabel.allCases.count)
        #expect(all.allSatisfy { $0.isSystem })
        let byGroup = Dictionary(grouping: all, by: \.group)
        #expect(byGroup[.domain]?.count == 4)
        #expect(byGroup[.gate]?.count == 2)
    }

    @MainActor
    @Test("seedSystemLabels is idempotent")
    func seedIsIdempotent() throws {
        let (repo, _) = try makeRepo()
        try repo.seedSystemLabels()
        try repo.seedSystemLabels()
        #expect(try repo.allActive().count == SystemLabel.allCases.count)
    }

    @MainActor
    @Test("seed does not duplicate a pre-existing SYSTEM label of the same identity (legacy)")
    func seedRespectsExistingSystemLabel() throws {
        let (repo, _) = try makeRepo()
        // A legacy system "bug" seeded before stable ids (random id, isSystem=true).
        _ = try repo.create(name: "bug", group: .domain, isSystem: true)
        try repo.seedSystemLabels()
        let bugs = try repo.allActive().filter { $0.name.lowercased() == "bug" }
        #expect(bugs.count == 1)
        #expect(try repo.allActive().count == SystemLabel.allCases.count)
    }

    @MainActor
    @Test("a user's same-named free label does NOT block the canonical system label (P4)")
    func seedIsNotBlockedByUserLabel() throws {
        let (repo, _) = try makeRepo()
        // A user's own "bug" label (not a system label) must not suppress the
        // canonical system "bug" + its stable id (which suggestedAgent keys on).
        _ = try repo.create(name: "bug", group: .free, isSystem: false)
        try repo.seedSystemLabels()

        let systemBug = try repo.allActive().first { $0.id == SystemLabel.bug.id }
        #expect(systemBug != nil)
        #expect(systemBug?.isSystem == true)
        // Both the user's bug and the system bug now exist.
        #expect(try repo.allActive().filter { $0.name.lowercased() == "bug" }.count == 2)
        #expect(try repo.allActive().count == SystemLabel.allCases.count + 1)
    }

    @MainActor
    @Test("a soft-deleted system label does not re-seed as a duplicate (P4)")
    func seedDoesNotDuplicateTombstonedSystemLabel() throws {
        let (repo, context) = try makeRepo()
        try repo.seedSystemLabels()
        let bug = try #require(try repo.allActive().first { $0.id == SystemLabel.bug.id })
        try repo.softDelete(bug)

        try repo.seedSystemLabels()
        // Counting ALL rows (incl. the tombstone): still exactly one bug-id row.
        let bugRows = try context.fetch(FetchDescriptor<Label>()).filter { $0.id == SystemLabel.bug.id }
        #expect(bugRows.count == 1)
    }

    // MARK: - Agent queue (spec §8)

    @MainActor
    @Test("agentQueue returns todo/inProgress tasks for the agent and excludes others")
    func agentQueueFiltersCorrectly() throws {
        let (repo, context) = try makeRepo()
        let taskRepo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })

        let todo = TaskItem(title: "codex todo", workflowState: .todo, assignedAgent: .codex)
        let inProgress = TaskItem(title: "codex in progress", workflowState: .inProgress, assignedAgent: .codex)
        let backlog = TaskItem(title: "codex backlog", workflowState: .backlog, assignedAgent: .codex)
        let done = TaskItem(title: "codex done", workflowState: .done, assignedAgent: .codex)
        let otherAgent = TaskItem(title: "claude todo", workflowState: .todo, assignedAgent: .claude)
        let unassigned = TaskItem(title: "self todo", workflowState: .todo, assignedAgent: nil)
        let deleted = TaskItem(title: "codex deleted", workflowState: .inProgress, assignedAgent: .codex)
        deleted.deletedAt = .now

        for task in [todo, inProgress, backlog, done, otherAgent, unassigned, deleted] {
            try taskRepo.insert(task)
        }

        let queue = try repo.agentQueue(for: .codex)
        #expect(Set(queue.map(\.title)) == ["codex todo", "codex in progress"])
    }

    @MainActor
    @Test("agentQueue is empty for an agent with no matching tasks")
    func agentQueueEmpty() throws {
        let (repo, context) = try makeRepo()
        let taskRepo = TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now })
        let task = TaskItem(title: "claude todo", workflowState: .todo, assignedAgent: .claude)
        try taskRepo.insert(task)
        #expect(try repo.agentQueue(for: .codex).isEmpty)
    }
}
