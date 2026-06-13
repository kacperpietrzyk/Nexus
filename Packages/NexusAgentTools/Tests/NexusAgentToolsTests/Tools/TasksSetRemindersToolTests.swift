import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("tasks.set_reminders")
struct TasksSetRemindersToolTests {
    @Test("sets an absolute reminder on a task")
    @MainActor
    func setsAbsolute() async throws {
        let task = TaskItem(title: "Pay rent")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let out = try await TasksSetRemindersTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "reminders": .array([
                    .object(["kind": .string("absolute"), "at": .string("2026-06-20T09:00:00Z")])
                ]),
            ]),
            context: context
        )
        #expect(out["reminder_count"]?.intValue == 1)
        #expect(task.reminders.count == 1)
    }

    @Test("sets a relative reminder with anchor and offset")
    @MainActor
    func setsRelative() async throws {
        let task = TaskItem(title: "Prep deck")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let out = try await TasksSetRemindersTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "reminders": .array([
                    .object([
                        "kind": .string("relative"),
                        "offset": .double(-3600),
                        "anchor": .string("deadline"),
                    ])
                ]),
            ]),
            context: context
        )
        #expect(out["reminder_count"]?.intValue == 1)
        #expect(task.reminders == [.relative(offset: -3600, anchor: .deadline)])
    }

    @Test("sets a repeating absolute reminder")
    @MainActor
    func setsAbsoluteRepeating() async throws {
        let task = TaskItem(title: "Standup")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        _ = try await TasksSetRemindersTool().call(
            args: .object([
                "task_id": .string(task.id.uuidString),
                "reminders": .array([
                    .object([
                        "kind": .string("absolute"),
                        "at": .string("2026-06-20T09:00:00Z"),
                        "repeat": .string("weekly"),
                    ])
                ]),
            ]),
            context: context
        )
        guard case .absolute(_, let repeats) = task.reminders.first else {
            Issue.record("expected an absolute reminder")
            return
        }
        #expect(repeats == .weekly)
    }

    @Test("rejects an unrecognized repeat value")
    @MainActor
    func rejectsBadRepeat() async throws {
        let task = TaskItem(title: "X")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await TasksSetRemindersTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "reminders": .array([
                        .object([
                            "kind": .string("absolute"),
                            "at": .string("2026-06-20T09:00:00Z"),
                            "repeat": .string("monthly"),
                        ])
                    ]),
                ]),
                context: context
            )
        }
    }

    @Test("rejects a relative reminder missing offset")
    @MainActor
    func rejectsMissingOffset() async throws {
        let task = TaskItem(title: "X")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await TasksSetRemindersTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "reminders": .array([
                        .object(["kind": .string("relative"), "anchor": .string("due")])
                    ]),
                ]),
                context: context
            )
        }
    }

    @Test("rejects a relative reminder with an invalid anchor")
    @MainActor
    func rejectsInvalidAnchor() async throws {
        let task = TaskItem(title: "X")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await TasksSetRemindersTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "reminders": .array([
                        .object([
                            "kind": .string("relative"),
                            "offset": .double(-3600),
                            "anchor": .string("start"),
                        ])
                    ]),
                ]),
                context: context
            )
        }
    }

    @Test("rejects a non-array reminders value")
    @MainActor
    func rejectsNonArrayReminders() async throws {
        let task = TaskItem(title: "X")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await TasksSetRemindersTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "reminders": .string("nope"),
                ]),
                context: context
            )
        }
    }

    @Test("empty array clears reminders")
    @MainActor
    func clears() async throws {
        let task = TaskItem(title: "X")
        task.reminders = [.absolute(at: Date(timeIntervalSince1970: 1_700_000_000), repeats: nil)]
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        _ = try await TasksSetRemindersTool().call(
            args: .object(["task_id": .string(task.id.uuidString), "reminders": .array([])]),
            context: context
        )
        #expect(task.reminders.isEmpty)
    }

    @Test("rejects an unknown reminder kind")
    @MainActor
    func rejectsUnknownKind() async throws {
        let task = TaskItem(title: "X")
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await TasksSetRemindersTool().call(
                args: .object([
                    "task_id": .string(task.id.uuidString),
                    "reminders": .array([.object(["kind": .string("nope")])]),
                ]),
                context: context
            )
        }
    }
}
