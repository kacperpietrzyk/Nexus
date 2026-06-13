import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("search.global")
struct SearchGlobalToolTests {
    @Test("returns hits across kinds for a query")
    @MainActor
    func searchesAllKinds() async throws {
        let task = TaskItem(title: "Quarterly report draft")
        let (context, _, _) = try await InMemoryAgentContext.make(tasks: [task])

        let out = try await SearchGlobalTool().call(
            args: .object(["query": .string("quarterly")]),
            context: context
        )

        let results = out["results"]?.arrayValue
        #expect(results?.contains { $0["id"]?.stringValue == task.id.uuidString } == true)
        #expect(results?.contains { $0["kind"]?.stringValue == "task" } == true)
    }

    @Test("missing query throws validation")
    @MainActor
    func missingQueryThrows() async throws {
        let (context, _, _) = try await InMemoryAgentContext.make()

        await #expect(throws: AgentError.self) {
            _ = try await SearchGlobalTool().call(args: .object([:]), context: context)
        }
    }
}
