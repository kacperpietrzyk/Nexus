import CommandPaletteShell
import Foundation
import InboxShell
import NexusCore
import SwiftData
import TasksFeature
import Testing

@MainActor
@Suite("Task command registration")
struct TaskCommandTests {

    @Test("bootstrap registers Inbox sources and six task commands")
    func bootstrapRegistersSourcesAndCommands() async throws {
        let harness = try Harness()
        let inbox = InboxSourceRegistry()
        let commands = CommandRegistry()

        await TasksComposition.bootstrap(
            repository: harness.repository,
            inboxRegistry: inbox,
            commandRegistry: commands,
            navigation: .init(goToToday: {}, goToInbox: {}, openCapture: {}, selectedTask: { nil })
        )

        #expect(await inbox.sourceIDs() == ["tasks.no-date", "tasks.snoozed"])
        #expect(
            await commands.allCommands().map(\.id) == [
                "tasks.add",
                "tasks.go-inbox",
                "tasks.go-today",
                "tasks.mark-selected-done",
                "tasks.snooze-selected",
                "tasks.toggle-focus",
            ])
    }

    @Test("mark selected done command mutates selected task")
    func markSelectedDone() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Finish report")
        try harness.repository.insert(task)
        let command = MarkSelectedDoneCommand(repository: harness.repository, selectedTask: { task })

        try await command.execute()

        #expect(task.status == .done)
    }

    @Test("mark selected done command cascades open subtasks")
    func markSelectedDoneCascadesOpenSubtasks() async throws {
        let harness = try Harness()
        let parent = TaskItem(title: "Parent")
        let child = TaskItem(title: "Child", parentTaskID: parent.id)
        try harness.repository.insert(parent)
        try harness.repository.insert(child)
        let command = MarkSelectedDoneCommand(repository: harness.repository, selectedTask: { parent })

        try await command.execute()

        #expect(parent.status == .done)
        #expect(child.status == .done)
    }

    @Test("selected task commands are unavailable without selection")
    func selectedTaskCommandsUnavailableWithoutSelection() async throws {
        let harness = try Harness()
        let markDone = MarkSelectedDoneCommand(repository: harness.repository, selectedTask: { nil })
        let snooze = SnoozeSelectedCommand(repository: harness.repository, selectedTask: { nil })
        let focus = ToggleFocusCommand(repository: harness.repository, selectedTask: { nil })

        #expect(await markDone.availability == .disabled(reason: "Select a task first"))
        #expect(await snooze.availability == .disabled(reason: "Select a task first"))
        #expect(await focus.availability == .disabled(reason: "Select a task first"))
    }

    @Test("registry does not execute selected task command without selection")
    func registryDoesNotExecuteSelectedTaskCommandWithoutSelection() async throws {
        let harness = try Harness()
        let task = TaskItem(title: "Write update")
        try harness.repository.insert(task)
        let registry = CommandRegistry()
        let command = MarkSelectedDoneCommand(repository: harness.repository, selectedTask: { nil })
        await registry.register(command)

        await #expect(
            throws: CommandRegistryError.disabledCommand(
                "tasks.mark-selected-done",
                reason: "Select a task first"
            )
        ) {
            try await registry.execute(id: "tasks.mark-selected-done")
        }

        #expect(task.status == .open)
    }
}

@MainActor
private struct Harness {
    let container: ModelContainer
    let repository: TaskItemRepository

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: TaskItem.self, configurations: config)
        self.repository = TaskItemRepository(
            context: container.mainContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }
}
