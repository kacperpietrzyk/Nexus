import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("search.global")
struct SearchGlobalToolTests {
    @Test("returns a ranked hit for a query with no kind filter")
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

    @Test("kinds filter including the matching kind returns the hit")
    @MainActor
    func kindsFilterMatches() async throws {
        let task = TaskItem(title: "Quarterly report draft")
        let (context, _, _) = try await InMemoryAgentContext.make(tasks: [task])

        let out = try await SearchGlobalTool().call(
            args: .object(["query": .string("quarterly"), "kinds": .array([.string("task")])]),
            context: context
        )

        let results = out["results"]?.arrayValue
        #expect(results?.contains { $0["id"]?.stringValue == task.id.uuidString } == true)
    }

    @Test("kinds filter excluding the matching kind returns nothing")
    @MainActor
    func kindsFilterExcludes() async throws {
        let task = TaskItem(title: "Quarterly report draft")
        let (context, _, _) = try await InMemoryAgentContext.make(tasks: [task])

        let out = try await SearchGlobalTool().call(
            args: .object(["query": .string("quarterly"), "kinds": .array([.string("note")])]),
            context: context
        )

        #expect(out["results"]?.arrayValue?.isEmpty == true)
    }

    @Test("kinds with only unrecognised values throws validation")
    @MainActor
    func kindsAllInvalidThrows() async throws {
        let (context, _, _) = try await InMemoryAgentContext.make(tasks: [TaskItem(title: "x")])

        await #expect(throws: AgentError.self) {
            _ = try await SearchGlobalTool().call(
                args: .object(["query": .string("x"), "kinds": .array([.string("bogus_typo")])]),
                context: context
            )
        }
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
