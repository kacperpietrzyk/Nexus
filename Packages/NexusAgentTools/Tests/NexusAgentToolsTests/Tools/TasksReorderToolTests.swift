import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

@MainActor
struct TasksReorderToolTests {
    @Test("reorder assigns sequential order in the given order")
    func reorders() async throws {
        let a = TaskItem(title: "A")
        let b = TaskItem(title: "B")
        let c = TaskItem(title: "C")
        let fixture = try await InMemoryAgentContext.make(tasks: [a, b, c])
        let args = JSONValue.object([
            "ordered_ids": .array([.string(c.id.uuidString), .string(a.id.uuidString), .string(b.id.uuidString)])
        ])
        _ = try await TasksReorderTool().call(args: args, context: fixture.context)
        let cOrder = try #require(c.orderIndex)
        let aOrder = try #require(a.orderIndex)
        let bOrder = try #require(b.orderIndex)
        #expect(cOrder < aOrder)
        #expect(aOrder < bOrder)
    }

    @Test("unknown id is a not_found error")
    func unknownID() async throws {
        let a = TaskItem(title: "A")
        let fixture = try await InMemoryAgentContext.make(tasks: [a])
        let args = JSONValue.object(["ordered_ids": .array([.string(UUID().uuidString)])])
        await #expect(throws: AgentError.self) {
            _ = try await TasksReorderTool().call(args: args, context: fixture.context)
        }
    }

    @Test("empty ordered_ids is a validation error")
    func emptyIDs() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object(["ordered_ids": .array([])])
        await #expect(throws: AgentError.self) {
            _ = try await TasksReorderTool().call(args: args, context: fixture.context)
        }
    }
}
