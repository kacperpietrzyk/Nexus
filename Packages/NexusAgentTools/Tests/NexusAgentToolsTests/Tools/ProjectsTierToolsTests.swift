import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@Suite("ProjectsTierTools")
struct ProjectsTierToolsTests {
    // MARK: - Reconciliation: workflow_state write routes through repository (I1, table 5.1)

    /// The core correctness assertion the brief demands: writing each `WorkflowState`
    /// via the MCP tool routes through `setWorkflowState`, so `status` is reconciled
    /// per table 5.1. This is an assertion, not a code-read.
    @MainActor
    @Test(
        "set_workflow_state forces status per table 5.1",
        arguments: [
            (WorkflowState.backlog, TaskStatus.open),
            (WorkflowState.todo, TaskStatus.open),
            (WorkflowState.inProgress, TaskStatus.open),
            (WorkflowState.inReview, TaskStatus.open),
            (WorkflowState.done, TaskStatus.done),
            (WorkflowState.canceled, TaskStatus.done),
            (WorkflowState.duplicate, TaskStatus.done),
        ]
    )
    func setWorkflowStateForcesStatus(_ state: WorkflowState, _ expected: TaskStatus) async throws {
        let task = TaskItem(title: "reconcile")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let result = try await TasksSetWorkflowStateTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "workflow_state": .string(state.rawValue),
            ]),
            context: fixture.context
        )

        let dto = try TasksToolJSON.decode(TaskDTO.self, from: result)
        #expect(dto.workflowState == state.rawValue)
        #expect(task.status == expected)
        #expect(task.workflowState == state)
    }

    @MainActor
    @Test("set_workflow_state done sets lastCompletedAt; canceled/duplicate do not (I4)")
    func doneSetsCompletionButTerminalDoesNot() async throws {
        let doneTask = TaskItem(title: "done")
        let canceledTask = TaskItem(title: "canceled")
        let dupTask = TaskItem(title: "dup")
        let fixture = try await InMemoryAgentContext.make(tasks: [doneTask, canceledTask, dupTask])

        _ = try await TasksSetWorkflowStateTool().call(
            args: .object(["task_id": .string(doneTask.id.uuidString), "workflow_state": .string("done")]),
            context: fixture.context
        )
        _ = try await TasksSetWorkflowStateTool().call(
            args: .object(["task_id": .string(canceledTask.id.uuidString), "workflow_state": .string("canceled")]),
            context: fixture.context
        )
        _ = try await TasksSetWorkflowStateTool().call(
            args: .object(["task_id": .string(dupTask.id.uuidString), "workflow_state": .string("duplicate")]),
            context: fixture.context
        )

        #expect(doneTask.status == .done)
        #expect(doneTask.lastCompletedAt != nil)
        #expect(canceledTask.status == .done)
        #expect(canceledTask.lastCompletedAt == nil)
        #expect(dupTask.status == .done)
        #expect(dupTask.lastCompletedAt == nil)
    }

    @MainActor
    @Test("set_workflow_state rejects null (no path back to a GTD task)")
    func rejectsNullWorkflowState() async throws {
        let task = TaskItem(title: "no-null")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksSetWorkflowStateTool().call(
                args: .object(["task_id": .string(task.id.uuidString), "workflow_state": .null]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("set_workflow_state rejects an unknown raw value")
    func rejectsUnknownWorkflowState() async throws {
        let task = TaskItem(title: "bad-state")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        await #expect(throws: AgentError.self) {
            _ = try await TasksSetWorkflowStateTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "workflow_state": .string("inflight"),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("set_workflow_state on missing task throws notFound")
    func setWorkflowStateMissingTask() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let missing = UUID().uuidString
        await #expect(throws: AgentError.self) {
            _ = try await TasksSetWorkflowStateTool().call(
                args: .object(["task_id": .string(missing), "workflow_state": .string("todo")]),
                context: fixture.context
            )
        }
    }

    // MARK: - GTD regression (I7): a nil-workflowState task is unchanged at the MCP layer

    /// I7 is the heaviest-weighted regression risk: a plain GTD task
    /// (`workflowState == nil`) must serialize identically to before the additive
    /// `TaskDTO` change. The `workflow_state`/`assigned_agent` keys must be ABSENT
    /// from the encoded JSON (not `null`), so any existing key-set snapshot is
    /// unaffected.
    @MainActor
    @Test("GTD task DTO omits workflow_state/assigned_agent keys (I7)")
    func gtdTaskDTOOmitsNewKeys() async throws {
        let task = TaskItem(title: "plain gtd")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let result = try await TasksGetTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        guard case .object(let fields) = result else {
            Issue.record("expected object DTO")
            return
        }
        #expect(fields["workflow_state"] == nil, "absent, not null, for a GTD task")
        #expect(fields["assigned_agent"] == nil, "absent, not null, for a GTD task")

        let dto = try TasksToolJSON.decode(TaskDTO.self, from: result)
        #expect(dto.workflowState == nil)
        #expect(dto.assignedAgent == nil)
        #expect(dto.state == "open")
    }

    /// The new Projects-tier code must never force a machine onto a GTD task: the
    /// existing complete/reopen MCP paths leave `workflowState == nil` (I7).
    @MainActor
    @Test("complete then reopen of a GTD task keeps workflowState nil (I7)")
    func gtdCompleteReopenKeepsNilWorkflow() async throws {
        let task = TaskItem(title: "gtd lifecycle")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksCompleteTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        #expect(task.status == .done)
        #expect(task.workflowState == nil, "completing a GTD task must not stamp a workflow state")

        _ = try await TasksReopenTool().call(
            args: .object(["task_id": .string(task.id.uuidString)]),
            context: fixture.context
        )
        #expect(task.status == .open)
        #expect(task.workflowState == nil, "reopening a GTD task must not stamp a workflow state")
    }

    // MARK: - Agent assignment (I8: pure metadata, status unchanged)

    @MainActor
    @Test("assign_agent sets agent without touching status (I8)")
    func assignAgentLeavesStatusUnchanged() async throws {
        let task = TaskItem(title: "assign")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let statusBefore = task.status

        let result = try await TasksAssignAgentTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "agent": .string("codex"),
            ]),
            context: fixture.context
        )

        let dto = try TasksToolJSON.decode(TaskDTO.self, from: result)
        #expect(dto.assignedAgent == "codex")
        #expect(task.assignedAgent == "codex")
        #expect(task.status == statusBefore)
        #expect(task.workflowState == nil, "assignment must not touch the workflow machine")
    }

    @MainActor
    @Test("assign_agent with null clears back to self")
    func assignAgentNullClears() async throws {
        let task = TaskItem(title: "clear", assignedAgent: .claude)
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        let result = try await TasksAssignAgentTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "agent": .null,
            ]),
            context: fixture.context
        )
        let dto = try TasksToolJSON.decode(TaskDTO.self, from: result)
        #expect(dto.assignedAgent == nil)
        #expect(task.assignedAgent == nil)
    }

    @MainActor
    @Test("assign_agent rejects an unknown agent")
    func assignAgentRejectsUnknown() async throws {
        let task = TaskItem(title: "bad-agent")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        await #expect(throws: AgentError.self) {
            _ = try await TasksAssignAgentTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "agent": .string("gemini"),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - Agent queue (§8)

    @MainActor
    @Test("agents.queue returns only the agent's todo/inProgress tasks")
    func agentQueueFilters() async throws {
        // codex: one todo (in), one inReview (out — not in {todo,inProgress}), one done (out).
        // claude: one inProgress (out of codex queue).
        let codexTodo = TaskItem(title: "codex-todo", workflowState: .todo, assignedAgent: .codex)
        let codexReview = TaskItem(title: "codex-review", workflowState: .inReview, assignedAgent: .codex)
        let codexDone = TaskItem(title: "codex-done", workflowState: .done, assignedAgent: .codex)
        let claudeInProg = TaskItem(title: "claude-inprog", workflowState: .inProgress, assignedAgent: .claude)
        let unassignedTodo = TaskItem(title: "self-todo", workflowState: .todo)
        let fixture = try await InMemoryAgentContext.make(
            tasks: [codexTodo, codexReview, codexDone, claudeInProg, unassignedTodo]
        )

        let result = try await AgentsQueueTool().call(
            args: .object(["agent": .string("codex")]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([TaskDTO].self, from: result)
        #expect(dtos.map(\.title) == ["codex-todo"])
        #expect(dtos.first?.workflowState == "todo")
        #expect(dtos.first?.assignedAgent == "codex")
    }

    @MainActor
    @Test("agents.queue picks up a task after set_workflow_state + assign_agent")
    func agentQueueEndToEnd() async throws {
        let task = TaskItem(title: "pipeline")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])

        _ = try await TasksAssignAgentTool().call(
            args: .object(["task_id": .string(task.id.uuidString), "agent": .string("claude")]),
            context: fixture.context
        )
        _ = try await TasksSetWorkflowStateTool().call(
            args: .object(["task_id": .string(task.id.uuidString), "workflow_state": .string("inProgress")]),
            context: fixture.context
        )

        let result = try await AgentsQueueTool().call(
            args: .object(["agent": .string("claude")]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([TaskDTO].self, from: result)
        #expect(dtos.map(\.title) == ["pipeline"])
    }

    // MARK: - Project status (§4.1)

    @MainActor
    @Test("projects.set_status updates status; projects.get reads it back")
    func projectSetAndGetStatus() async throws {
        let project = Project(name: "ThreatForge")
        let fixture = try await InMemoryAgentContext.make()
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        let setResult = try await ProjectsSetStatusTool().call(
            args: .object([
                "project_id": .string(project.id.uuidString),
                "status": .string("active"),
            ]),
            context: fixture.context
        )
        let setDTO = try TasksToolJSON.decode(ProjectDTO.self, from: setResult)
        #expect(setDTO.status == "active")
        #expect(project.status == .active)

        let getResult = try await ProjectsGetTool().call(
            args: .object(["project_id": .string(project.id.uuidString)]),
            context: fixture.context
        )
        let getDTO = try TasksToolJSON.decode(ProjectDTO.self, from: getResult)
        #expect(getDTO.status == "active")
        #expect(getDTO.name == "ThreatForge")
    }

    @MainActor
    @Test("projects.set_status rejects an invalid status")
    func projectSetStatusRejectsInvalid() async throws {
        let project = Project(name: "Bad")
        let fixture = try await InMemoryAgentContext.make()
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()

        await #expect(throws: AgentError.self) {
            _ = try await ProjectsSetStatusTool().call(
                args: .object([
                    "project_id": .string(project.id.uuidString),
                    "status": .string("paused"),
                ]),
                context: fixture.context
            )
        }
    }

}

/// Labels (spec §7, single-select I5) and dependency-edge (spec §9) MCP tools. Split
/// from `ProjectsTierToolsTests` to keep each suite under the type-body length gate.
@Suite("ProjectsTierGraphTools")
struct ProjectsTierGraphToolsTests {
    // MARK: - Labels (§7, single-select I5)

    @MainActor
    @Test("labels.assign enforces domain single-select (I5)")
    func labelAssignSingleSelect() async throws {
        let task = TaskItem(title: "labeled")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let labelRepo = LabelRepository(context: fixture.repo.context)
        let bug = try labelRepo.create(name: "bug", group: .domain, isSystem: true)
        let feature = try labelRepo.create(name: "feature", group: .domain, isSystem: true)

        _ = try await LabelsAssignTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
                "label_id": .string(bug.id.uuidString),
            ]),
            context: fixture.context
        )
        // Assigning a second domain label replaces the first.
        let result = try await LabelsAssignTool().call(
            args: .object([
                "item_id": .string(task.id.uuidString),
                "item_kind": .string("task"),
                "label_id": .string(feature.id.uuidString),
            ]),
            context: fixture.context
        )
        let dtos = try TasksToolJSON.decode([LabelDTO].self, from: result)
        #expect(dtos.map(\.name) == ["feature"])
    }

    @MainActor
    @Test("labels.assign free accumulates; labels.remove detaches")
    func labelFreeAccumulatesAndRemove() async throws {
        let project = Project(name: "P")
        let fixture = try await InMemoryAgentContext.make()
        fixture.repo.context.insert(project)
        try fixture.repo.context.save()
        let labelRepo = LabelRepository(context: fixture.repo.context)
        let urgent = try labelRepo.create(name: "urgent", group: .free)
        let q3 = try labelRepo.create(name: "q3", group: .free)

        for label in [urgent, q3] {
            _ = try await LabelsAssignTool().call(
                args: .object([
                    "item_id": .string(project.id.uuidString),
                    "item_kind": .string("project"),
                    "label_id": .string(label.id.uuidString),
                ]),
                context: fixture.context
            )
        }
        let listResult = try await LabelsListForTool().call(
            args: .object([
                "item_id": .string(project.id.uuidString),
                "item_kind": .string("project"),
            ]),
            context: fixture.context
        )
        let listed = try TasksToolJSON.decode([LabelDTO].self, from: listResult)
        #expect(Set(listed.map(\.name)) == ["urgent", "q3"])

        let removeResult = try await LabelsRemoveTool().call(
            args: .object([
                "item_id": .string(project.id.uuidString),
                "item_kind": .string("project"),
                "label_id": .string(urgent.id.uuidString),
            ]),
            context: fixture.context
        )
        let remaining = try TasksToolJSON.decode([LabelDTO].self, from: removeResult)
        #expect(remaining.map(\.name) == ["q3"])
    }

    @MainActor
    @Test("labels.list_all returns active labels")
    func labelsListAll() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let labelRepo = LabelRepository(context: fixture.repo.context)
        _ = try labelRepo.create(name: "alpha", group: .free)
        _ = try labelRepo.create(name: "beta", group: .free)

        let result = try await LabelsListAllTool().call(args: .object([:]), context: fixture.context)
        let dtos = try TasksToolJSON.decode([LabelDTO].self, from: result)
        #expect(dtos.map(\.name) == ["alpha", "beta"])
    }

    @MainActor
    @Test("labels.assign on a missing label throws notFound")
    func labelAssignMissing() async throws {
        let task = TaskItem(title: "t")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        await #expect(throws: AgentError.self) {
            _ = try await LabelsAssignTool().call(
                args: .object([
                    "item_id": .string(task.id.uuidString),
                    "item_kind": .string("task"),
                    "label_id": .string(UUID().uuidString),
                ]),
                context: fixture.context
            )
        }
    }

    // MARK: - Blocks (§9)

    @MainActor
    @Test("blocks.add then blocks.list reports blocks + blocked_by")
    func blocksAddAndList() async throws {
        let blocker = TaskItem(title: "blocker")
        let blocked = TaskItem(title: "blocked")
        let fixture = try await InMemoryAgentContext.make(tasks: [blocker, blocked])

        let addResult = try await BlocksAddTool().call(
            args: .object([
                "from_id": .string(blocker.id.uuidString),
                "from_kind": .string("task"),
                "to_id": .string(blocked.id.uuidString),
                "to_kind": .string("task"),
            ]),
            context: fixture.context
        )
        let addDTO = try TasksToolJSON.decode(BlocksDTO.self, from: addResult)
        #expect(addDTO.blocks.map(\.id) == [blocked.id.uuidString])
        #expect(addDTO.blockedBy.isEmpty)

        // From the blocked task's perspective, it is blocked_by the blocker.
        let listResult = try await BlocksListTool().call(
            args: .object([
                "item_id": .string(blocked.id.uuidString),
                "item_kind": .string("task"),
            ]),
            context: fixture.context
        )
        let listDTO = try TasksToolJSON.decode(BlocksDTO.self, from: listResult)
        #expect(listDTO.blockedBy.map(\.id) == [blocker.id.uuidString])
        #expect(listDTO.blocks.isEmpty)
    }

    @MainActor
    @Test("blocks.add rejects a hallucinated endpoint instead of minting a dangling edge (A2)")
    func blocksAddValidatesEndpoints() async throws {
        let blocker = TaskItem(title: "blocker")
        let fixture = try await InMemoryAgentContext.make(tasks: [blocker])
        let phantomID = UUID()

        await #expect(throws: AgentError.self) {
            _ = try await BlocksAddTool().call(
                args: .object([
                    "from_id": .string(blocker.id.uuidString),
                    "from_kind": .string("task"),
                    "to_id": .string(phantomID.uuidString),
                    "to_kind": .string("task"),
                ]),
                context: fixture.context
            )
        }
        // No edge should have been created from the (real) source.
        let view = try await BlocksListTool().call(
            args: .object(["item_id": .string(blocker.id.uuidString), "item_kind": .string("task")]),
            context: fixture.context
        )
        #expect(try TasksToolJSON.decode(BlocksDTO.self, from: view).blocks.isEmpty)
    }

    @MainActor
    @Test("labels.assign rejects a hallucinated endpoint item (A2)")
    func labelAssignValidatesEndpoint() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let labelRepo = LabelRepository(context: fixture.repo.context)
        let urgent = try labelRepo.create(name: "urgent", group: .free)

        await #expect(throws: AgentError.self) {
            _ = try await LabelsAssignTool().call(
                args: .object([
                    "item_id": .string(UUID().uuidString),
                    "item_kind": .string("task"),
                    "label_id": .string(urgent.id.uuidString),
                ]),
                context: fixture.context
            )
        }
    }

    @MainActor
    @Test("blocks.add is idempotent and blocks.remove detaches")
    func blocksIdempotentAndRemove() async throws {
        let blocker = TaskItem(title: "a")
        let blocked = TaskItem(title: "b")
        let fixture = try await InMemoryAgentContext.make(tasks: [blocker, blocked])
        let args = JSONValue.object([
            "from_id": .string(blocker.id.uuidString),
            "from_kind": .string("task"),
            "to_id": .string(blocked.id.uuidString),
            "to_kind": .string("task"),
        ])

        _ = try await BlocksAddTool().call(args: args, context: fixture.context)
        let secondAdd = try await BlocksAddTool().call(args: args, context: fixture.context)
        let secondDTO = try TasksToolJSON.decode(BlocksDTO.self, from: secondAdd)
        #expect(secondDTO.blocks.count == 1, "idempotent: no duplicate edge")

        let removeResult = try await BlocksRemoveTool().call(args: args, context: fixture.context)
        let removeDTO = try TasksToolJSON.decode(BlocksDTO.self, from: removeResult)
        #expect(removeDTO.blocks.isEmpty)
    }

    @MainActor
    @Test("blocks.add rejects a self edge")
    func blocksRejectsSelfEdge() async throws {
        let task = TaskItem(title: "self")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        await #expect(throws: AgentError.self) {
            _ = try await BlocksAddTool().call(
                args: .object([
                    "from_id": .string(task.id.uuidString),
                    "from_kind": .string("task"),
                    "to_id": .string(task.id.uuidString),
                    "to_kind": .string("task"),
                ]),
                context: fixture.context
            )
        }
    }
}
