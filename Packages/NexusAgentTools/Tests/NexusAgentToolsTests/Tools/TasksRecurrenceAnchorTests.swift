import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct TasksRecurrenceAnchorTests {
    @Test("create with recurrence_anchor=completion sets the rule anchor")
    func anchorCompletion() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("Water plants"),
            "recurrence_rule": .string("FREQ=DAILY"),
            "recurrence_anchor": .string("completion"),
        ])
        let result = try await TasksCreateTool().call(args: args, context: fixture.context)
        let id = try #require(result["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let task = try TasksMutationToolSupport.liveTask(id: id, context: fixture.context)
        let rule = try RRuleParser.parse(#require(task.recurrenceRule))
        #expect(rule.anchor == .completion)
    }

    @Test("create without recurrence_anchor defaults to due-date anchor")
    func anchorDefault() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("Pay rent"),
            "recurrence_rule": .string("FREQ=MONTHLY"),
        ])
        let result = try await TasksCreateTool().call(args: args, context: fixture.context)
        let id = try #require(result["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let task = try TasksMutationToolSupport.liveTask(id: id, context: fixture.context)
        let rule = try RRuleParser.parse(#require(task.recurrenceRule))
        #expect(rule.anchor == .dueDate)
    }

    @Test("update with recurrence_anchor=completion sets the rule anchor")
    func updateAnchorCompletion() async throws {
        let task = TaskItem(title: "Existing", recurrenceRule: "FREQ=DAILY")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let args = JSONValue.object([
            "task_id": .string(task.id.uuidString),
            "patch": .object([
                "recurrence_rule": .string("FREQ=WEEKLY"),
                "recurrence_anchor": .string("completion"),
            ]),
        ])
        _ = try await TasksUpdateTool().call(args: args, context: fixture.context)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        let rule = try RRuleParser.parse(#require(stored.recurrenceRule))
        #expect(rule.frequency == .weekly)
        #expect(rule.anchor == .completion)
    }

    @Test("update with recurrence_anchor only re-anchors the existing rule")
    func updateAnchorOnly() async throws {
        let task = TaskItem(title: "Existing", recurrenceRule: "FREQ=DAILY")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let args = JSONValue.object([
            "task_id": .string(task.id.uuidString),
            "patch": .object([
                "recurrence_anchor": .string("completion")
            ]),
        ])
        _ = try await TasksUpdateTool().call(args: args, context: fixture.context)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        let rule = try RRuleParser.parse(#require(stored.recurrenceRule))
        #expect(rule.frequency == .daily)
        #expect(rule.anchor == .completion)
    }

    @Test("update with recurrence_anchor=due_date strips an inline completion token")
    func updateAnchorBackToDue() async throws {
        let task = TaskItem(title: "Existing", recurrenceRule: "FREQ=DAILY;ANCHOR=COMPLETION")
        let fixture = try await InMemoryAgentContext.make(tasks: [task])
        let args = JSONValue.object([
            "task_id": .string(task.id.uuidString),
            "patch": .object([
                "recurrence_anchor": .string("due_date")
            ]),
        ])
        _ = try await TasksUpdateTool().call(args: args, context: fixture.context)
        let stored = try TasksMutationToolSupport.liveTask(id: task.id, context: fixture.context)
        let storedRule = try #require(stored.recurrenceRule)
        let rule = try RRuleParser.parse(storedRule)
        #expect(rule.anchor == .dueDate)
        #expect(!RRuleAnchorToken.isCompletionAnchored(storedRule))
    }

    @Test("create recurrence_anchor=due_date overrides an inline completion token")
    func createAnchorOverridesInline() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("Override"),
            "recurrence_rule": .string("FREQ=DAILY;ANCHOR=COMPLETION"),
            "recurrence_anchor": .string("due_date"),
        ])
        let result = try await TasksCreateTool().call(args: args, context: fixture.context)
        let id = try #require(result["id"]?.stringValue.flatMap(UUID.init(uuidString:)))
        let task = try TasksMutationToolSupport.liveTask(id: id, context: fixture.context)
        let rule = try RRuleParser.parse(#require(task.recurrenceRule))
        #expect(rule.anchor == .dueDate)
    }

    @Test("invalid recurrence_anchor is rejected")
    func invalidAnchor() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "title": .string("Bad anchor"),
            "recurrence_rule": .string("FREQ=DAILY"),
            "recurrence_anchor": .string("complete"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await TasksCreateTool().call(args: args, context: fixture.context)
        }
    }
}
