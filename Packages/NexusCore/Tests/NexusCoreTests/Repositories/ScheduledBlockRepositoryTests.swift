import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("ScheduledBlockRepository")
struct ScheduledBlockRepositoryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([TaskItem.self, ScheduledBlock.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private let t0 = Date(timeIntervalSince1970: 1_780_000_000)

    @MainActor
    @Test("create persists a block and wires the scheduledAs edge")
    func createWiresEdge() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let links = LinkRepository(context: context)
        let taskID = UUID()
        let block = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800), title: "do it")

        #expect(block.status == .proposed)
        #expect(try repo.find(block.id)?.id == block.id)

        let outgoing = try links.outgoing(from: (.task, taskID))
        #expect(outgoing.contains { $0.toID == block.id && $0.linkKind == .scheduledAs })
    }

    @MainActor
    @Test("blocks(for:) returns live blocks for a task, earliest first")
    func blocksForTask() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let taskID = UUID()
        let later = try repo.create(taskID: taskID, start: t0.addingTimeInterval(7200), end: t0.addingTimeInterval(9000))
        let earlier = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800))
        let listed = try repo.blocks(for: taskID)
        #expect(listed.map(\.id) == [earlier.id, later.id])
    }

    @MainActor
    @Test("soft delete hides the block and removes its edge")
    func softDeleteHides() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let links = LinkRepository(context: context)
        let taskID = UUID()
        let block = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800))
        try repo.softDelete(block)

        #expect(try repo.find(block.id) == nil)
        #expect(try repo.blocks(for: taskID).isEmpty)
        #expect(try links.outgoing(from: (.task, taskID)).isEmpty)
    }

    @MainActor
    @Test("reschedule moves start/end and bumps updatedAt")
    func reschedule() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let block = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800))
        let before = block.updatedAt
        try repo.reschedule(block, start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400))
        #expect(block.start == t0.addingTimeInterval(3600))
        #expect(block.end == t0.addingTimeInterval(5400))
        #expect(block.updatedAt >= before)
    }

    @MainActor
    @Test("markAccepted flips status and records external event id (invariant §14)")
    func markAccepted() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let block = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800))
        #expect(block.externalEventID == nil)
        try repo.markAccepted(block, externalEventID: "ek-123")
        #expect(block.status == .accepted)
        #expect(block.externalEventID == "ek-123")
    }

    @MainActor
    @Test("softDeleteAll cascades every block for a task")
    func softDeleteAll() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let taskID = UUID()
        _ = try repo.create(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800))
        _ = try repo.create(taskID: taskID, start: t0.addingTimeInterval(3600), end: t0.addingTimeInterval(5400))
        let deleted = try repo.softDeleteAll(for: taskID)
        #expect(deleted.count == 2)
        #expect(try repo.blocks(for: taskID).isEmpty)
    }

    @MainActor
    @Test("persistProposal materializes a BlockProposal as a proposed/auto block")
    func persistProposal() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        let taskID = UUID()
        let proposal = BlockProposal(taskID: taskID, start: t0, end: t0.addingTimeInterval(1800), title: "p")
        let block = try repo.persistProposal(proposal)
        #expect(block.status == .proposed)
        #expect(block.origin == .auto)
        #expect(block.title == "p")
    }

    @MainActor
    @Test("blocks(from:to:) returns blocks overlapping a window")
    func blocksInWindow() throws {
        let context = try makeContext()
        let repo = ScheduledBlockRepository(context: context)
        _ = try repo.create(taskID: UUID(), start: t0, end: t0.addingTimeInterval(1800))
        _ = try repo.create(taskID: UUID(), start: t0.addingTimeInterval(100_000), end: t0.addingTimeInterval(101_800))
        let inWindow = try repo.blocks(from: t0.addingTimeInterval(-100), to: t0.addingTimeInterval(3600))
        #expect(inWindow.count == 1)
    }
}
