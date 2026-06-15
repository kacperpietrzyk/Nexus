import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("cycles write")
struct CyclesWriteToolsTests {
    private static let startISO = "2026-06-15T00:00:00Z"
    private static let endISO = "2026-06-29T00:00:00Z"

    @Test("cycles.create creates an upcoming cycle")
    @MainActor
    func create() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let out = try await CyclesCreateTool().call(
            args: .object([
                "name": .string("Sprint 1"),
                "start_at": .string(Self.startISO),
                "end_at": .string(Self.endISO),
            ]),
            context: context
        )
        #expect(out["name"]?.stringValue == "Sprint 1")
        #expect(out["id"]?.stringValue != nil)
        #expect(out["status"]?.stringValue == CycleStatus.upcoming.rawValue)
    }

    @Test("cycles.create rejects end_at <= start_at")
    @MainActor
    func createRejectsBadRange() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await CyclesCreateTool().call(
                args: .object([
                    "name": .string("Bad"),
                    "start_at": .string(Self.endISO),
                    "end_at": .string(Self.startISO),
                ]),
                context: context
            )
        }
    }

    @Test("cycles.update changes name and dates")
    @MainActor
    func update() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let repo = CycleRepository(context: context.modelContext.context, now: context.now)
        let cycle = try repo.create(name: "Old", startAt: .now, endAt: .now.addingTimeInterval(86_400))
        let out = try await CyclesUpdateTool().call(
            args: .object([
                "cycle_id": .string(cycle.id.uuidString),
                "name": .string("New"),
                "start_at": .string(Self.startISO),
                "end_at": .string(Self.endISO),
            ]),
            context: context
        )
        #expect(out["name"]?.stringValue == "New")
        // CycleDTO serializes dates with fractional seconds (CycleDTO.swift:43),
        // so the round-tripped strings carry the `.000` fraction. Asserting them
        // proves the new dates propagated through CycleRepository.update.
        #expect(out["start_at"]?.stringValue == "2026-06-15T00:00:00.000Z")
        #expect(out["end_at"]?.stringValue == "2026-06-29T00:00:00.000Z")
    }

    @Test("requiredISODate parses fractional seconds and rejects bad input")
    func requiredISODateParsing() throws {
        let fractional = try CyclesToolSupport.requiredISODate(
            .string("2026-06-15T00:00:00.000Z"),
            field: "start_at"
        )
        let plain = try CyclesToolSupport.requiredISODate(.string(Self.startISO), field: "start_at")
        #expect(fractional == plain)

        #expect(throws: AgentError.self) {
            _ = try CyclesToolSupport.requiredISODate(.string("not-a-date"), field: "start_at")
        }
        #expect(throws: AgentError.self) {
            _ = try CyclesToolSupport.requiredISODate(nil, field: "start_at")
        }
    }

    @Test("cycles.set_status activates a cycle")
    @MainActor
    func setStatus() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let repo = CycleRepository(context: context.modelContext.context, now: context.now)
        let cycle = try repo.create(name: "S", startAt: .now, endAt: .now.addingTimeInterval(86_400))
        let out = try await CyclesSetStatusTool().call(
            args: .object(["cycle_id": .string(cycle.id.uuidString), "status": .string("active")]),
            context: context
        )
        #expect(out["status"]?.stringValue == "active")
    }

    @Test("cycles.delete soft-deletes")
    @MainActor
    func delete() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let repo = CycleRepository(context: context.modelContext.context, now: context.now)
        let cycle = try repo.create(name: "S", startAt: .now, endAt: .now.addingTimeInterval(86_400))
        let out = try await CyclesDeleteTool().call(
            args: .object(["cycle_id": .string(cycle.id.uuidString)]),
            context: context
        )
        #expect(out["deleted"]?.boolValue == true)
        // `CycleRepository.find` does NOT filter soft-deleted rows (ProjectRepository
        // contract — see CycleRepository.swift:93), so assert the tombstone, not nil.
        #expect(try repo.find(id: cycle.id)?.deletedAt != nil)
    }
}
