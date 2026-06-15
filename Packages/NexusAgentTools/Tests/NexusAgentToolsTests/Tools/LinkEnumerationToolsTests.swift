import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct LinkEnumerationToolsTests {
    @Test("backlinks returns incoming edges to the endpoint")
    func backlinks() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let note = UUID()
        let task = UUID()
        _ = try fixture.context.linkRepository.findOrCreate(
            from: (.task, task),
            to: (.note, note),
            linkKind: .mentions
        )
        let args = JSONValue.object([
            "endpoint_id": .string(note.uuidString),
            "endpoint_kind": .string("note"),
        ])
        let result = try await LinksBacklinksTool().call(args: args, context: fixture.context)
        let dtos = try TasksToolJSON.decode([LinkDTO].self, from: result["links"]!)
        #expect(dtos.count == 1)
        #expect(dtos.first?.fromID == task.uuidString)
        #expect(dtos.first?.toID == note.uuidString)
    }

    @Test("invalid endpoint_kind is a validation error")
    func invalidKind() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let args = JSONValue.object([
            "endpoint_id": .string(UUID().uuidString),
            "endpoint_kind": .string("banana"),
        ])
        await #expect(throws: AgentError.self) {
            _ = try await LinksBacklinksTool().call(args: args, context: fixture.context)
        }
    }

    @Test("list truncates to the given limit")
    func listTruncates() async throws {
        let fixture = try await InMemoryAgentContext.make()
        for _ in 0..<3 {
            _ = try fixture.context.linkRepository.findOrCreate(
                from: (.task, UUID()), to: (.note, UUID()), linkKind: .mentions
            )
        }
        let args = JSONValue.object(["limit": .int(2)])
        let result = try await LinksListTool().call(args: args, context: fixture.context)
        let dtos = try TasksToolJSON.decode([LinkDTO].self, from: result["links"]!)
        #expect(dtos.count == 2)
    }
}
