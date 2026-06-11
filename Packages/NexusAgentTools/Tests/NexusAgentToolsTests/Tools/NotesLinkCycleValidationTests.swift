import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgentTools

/// `AgentEndpointValidator` coverage for the V13 `.cycle` endpoint kind
/// (Tranche 2, Plan A review follow-up). Edge tools accept any `ItemKind`, so
/// a cycle endpoint must be existence-checked like `.project`/`.label` — a
/// hallucinated or soft-deleted cycle id must never mint a dangling edge (A2).
@Suite("NotesLink cycle endpoint validation")
struct NotesLinkCycleValidationTests {
    @MainActor
    @Test("link validates cycle endpoints: live cycle accepted, hallucinated/soft-deleted rejected (A2)")
    func linkValidatesCycleTarget() async throws {
        let fixture = try await InMemoryAgentContext.make()
        let created = try await NotesCreateTool().call(
            args: .object(["title": .string("cycle linker")]),
            context: fixture.context
        )
        let noteID = try #require(UUID(uuidString: TasksToolJSON.decode(NoteDTO.self, from: created).id))

        // Hallucinated cycle id -> rejected, no dangling edge.
        await #expect(throws: AgentError.self) {
            _ = try await NotesLinkTool().call(
                args: .object([
                    "note_id": .string(noteID.uuidString),
                    "target_id": .string(UUID().uuidString),
                    "target_kind": .string("cycle"),
                    "kind": .string("source"),
                ]),
                context: fixture.context
            )
        }
        let danglingCount = try fixture.context.modelContext.context.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID }.count
        #expect(danglingCount == 0)

        // Live cycle -> accepted.
        let cycle = Cycle(name: "Sprint 1", startAt: .now, endAt: .now)
        fixture.context.modelContext.context.insert(cycle)
        try fixture.context.modelContext.context.save()
        _ = try await NotesLinkTool().call(
            args: .object([
                "note_id": .string(noteID.uuidString),
                "target_id": .string(cycle.id.uuidString),
                "target_kind": .string("cycle"),
                "kind": .string("source"),
            ]),
            context: fixture.context
        )
        let liveCount = try fixture.context.modelContext.context.fetch(FetchDescriptor<Link>())
            .filter { $0.fromID == noteID && $0.toID == cycle.id }.count
        #expect(liveCount == 1)

        // Soft-deleted cycle -> rejected again (dangling id reads as "no cycle").
        try fixture.context.cycleRepository.softDelete(cycle)
        await #expect(throws: AgentError.self) {
            _ = try await NotesLinkTool().call(
                args: .object([
                    "note_id": .string(noteID.uuidString),
                    "target_id": .string(cycle.id.uuidString),
                    "target_kind": .string("cycle"),
                    "kind": .string("mentions"),
                ]),
                context: fixture.context
            )
        }
    }
}
