import Foundation
import NexusAgentTools
import NexusCore
import Testing

@testable import NexusAgent

@MainActor
@Suite
struct AgentRecallToolTests {
    @Test
    func recallToolReturnsMatchingEntriesByScopeKeyQueryAndLimit() async throws {
        let harness = try ToolTestHarness.make()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)
        let secondDate = firstDate.addingTimeInterval(60)
        _ = try harness.store.upsert(
            scope: "global",
            key: "a",
            content: "Alpha memory",
            confidence: 0.9,
            now: firstDate
        )
        _ = try harness.store.upsert(
            scope: "global",
            key: "b",
            content: "Beta memory",
            confidence: 0.8,
            now: secondDate
        )
        _ = try harness.store.upsert(scope: "project:1", key: "a", content: "Alpha other")
        let tool = AgentRecallTool(store: harness.store)

        let scoped = try await tool.call(
            args: .object(["scope": .string("global")]),
            context: harness.agentContext
        )
        #expect(entries(in: scoped).count == 2)

        let keyed = try await tool.call(
            args: .object([
                "scope": .string("global"),
                "key": .string("a"),
            ]),
            context: harness.agentContext
        )
        #expect(entries(in: keyed).map(\.key) == ["a"])

        let queried = try await tool.call(
            args: .object([
                "scope": .string("global"),
                "query": .string("beta"),
            ]),
            context: harness.agentContext
        )
        #expect(entries(in: queried).map(\.content) == ["Beta memory"])

        let limited = try await tool.call(
            args: .object([
                "scope": .string("global"),
                "limit": .int(1),
            ]),
            context: harness.agentContext
        )
        #expect(entries(in: limited).map(\.key) == ["b"])
    }

    @Test
    func recallToolDefaultsToGlobalScopeAndLimitTen() async throws {
        let harness = try ToolTestHarness.make()
        for index in 0..<12 {
            _ = try harness.store.upsert(
                scope: "global",
                key: "k\(index)",
                content: "Memory \(index)",
                now: Date(timeIntervalSince1970: TimeInterval(1_800_000_000 + index))
            )
        }
        _ = try harness.store.upsert(scope: "project:1", key: "project", content: "Other")
        let tool = AgentRecallTool(store: harness.store)

        let output = try await tool.call(args: .object([:]), context: harness.agentContext)

        let results = entries(in: output)
        #expect(results.count == 10)
        #expect(results.allSatisfy { $0.scope == "global" })
    }

    @Test
    func recallToolReturnsEmptyForNonPositiveLimit() async throws {
        let harness = try ToolTestHarness.make()
        _ = try harness.store.upsert(scope: "global", key: "a", content: "Alpha")
        let tool = AgentRecallTool(store: harness.store)

        let output = try await tool.call(
            args: .object(["limit": .int(0)]),
            context: harness.agentContext
        )

        #expect(entries(in: output).isEmpty)
    }

    @Test
    func recallToolRejectsLimitAboveSchemaMaximum() async throws {
        let harness = try ToolTestHarness.make()
        let tool = AgentRecallTool(store: harness.store)

        await #expect(throws: AgentError.validation("limit must be between 0 and 1000")) {
            try await tool.call(
                args: .object(["limit": .int(1_001)]),
                context: harness.agentContext
            )
        }
    }

    @Test
    func recallToolRejectsInvalidInputShape() async throws {
        let harness = try ToolTestHarness.make()
        let tool = AgentRecallTool(store: harness.store)

        await #expect(throws: AgentError.validation("Input must be an object")) {
            try await tool.call(args: .array([]), context: harness.agentContext)
        }
    }

    private func entries(in output: JSONValue) -> [RecallEntry] {
        guard
            let object = output.objectValue,
            let values = object["entries"]?.arrayValue
        else {
            return []
        }
        return values.compactMap { value in
            guard
                let object = value.objectValue,
                let id = object["id"]?.stringValue,
                let scope = object["scope"]?.stringValue,
                let key = object["key"]?.stringValue,
                let content = object["content"]?.stringValue,
                let confidence = object["confidence"]?.doubleValue
            else {
                return nil
            }
            return RecallEntry(
                id: id,
                scope: scope,
                key: key,
                content: content,
                confidence: confidence,
                updatedAt: object["updatedAt"]?.stringValue
            )
        }
    }
}

private struct RecallEntry: Equatable {
    let id: String
    let scope: String
    let key: String
    let content: String
    let confidence: Double
    let updatedAt: String?
}
