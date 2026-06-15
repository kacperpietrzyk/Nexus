import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("PeopleSuggestDuplicatesTool")
struct PeopleSuggestDuplicatesToolTests {
    @MainActor
    @Test("returns a candidate when an existing person matches the query")
    func matches() async throws {
        let fixture = try await InMemoryAgentContext.make()
        _ = try fixture.context.personRepository.create(displayName: "Jane Smith")
        let args = JSONValue.object(["query": .string("jane smith")])

        let result = try await PeopleSuggestDuplicatesTool().call(args: args, context: fixture.context)

        let matches = result["matches"]?.arrayValue ?? []
        #expect(matches.count == 1)
        #expect(matches.first?["display_name"]?.stringValue == "Jane Smith")
    }

    @MainActor
    @Test("returns empty matches when nothing is similar")
    func noMatch() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object(["query": .string("Nobody Here At All")])

        let result = try await PeopleSuggestDuplicatesTool().call(args: args, context: fixture.context)

        #expect((result["matches"]?.arrayValue ?? []).isEmpty)
    }

    @MainActor
    @Test("requires query")
    func requiresQuery() async throws {
        let fixture = try await InMemoryAgentContext.make()
        await #expect(throws: AgentError.self) {
            _ = try await PeopleSuggestDuplicatesTool().call(args: .object([:]), context: fixture.context)
        }
    }
}
