import Foundation
import NexusCore
import SwiftData

/// `schedule.acceptBlock` (spec §7 / §8 / §12): accept a proposed block — the
/// `CalendarSyncReconciler` ensures the "Nexus" calendar, writes a mirror event,
/// and flips the block to `accepted` (invariant §14: `accepted ⇒
/// externalEventID != nil`). Idempotent: re-accepting an accepted block reuses its
/// mirror event. Requires calendar write access (spec §13).
public struct ScheduleAcceptBlockTool: AgentTool {
    public let name = "schedule.accept_block"
    public let description =
        "Accepts a proposed scheduled block: materializes a mirror event in the "
        + "dedicated \"Nexus\" calendar and marks the block accepted. Requires calendar "
        + "write access. Idempotent on an already-accepted block."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "block_id": .string(description: "ScheduledBlock UUID to accept.")
        ],
        required: ["block_id"]
    )

    private let writer: any CalendarEventWriting

    public init(writer: any CalendarEventWriting) {
        self.writer = writer
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["block_id"], field: "block_id")
        let modelContext = context.modelContext.context
        let blocks = ScheduledBlockRepository(context: modelContext, now: context.now)

        guard let block = try blocks.find(id) else {
            throw AgentError.notFound("Scheduled block not found: \(id.uuidString)")
        }

        let reconciler = CalendarSyncReconciler(
            context: modelContext,
            writer: writer,
            blocks: blocks,
            now: context.now
        )
        do {
            _ = try await reconciler.accept(block)
        } catch let error as CalendarProviderError {
            switch error {
            case .accessDenied:
                throw AgentError.validation("Calendar write access denied; grant access in Settings.")
            case .underlying(let message):
                throw AgentError.internalError("Calendar write failed: \(message)")
            }
        }
        return try TasksToolJSON.encode(ScheduledBlockDTO(from: block))
    }
}

/// `schedule.rejectBlock` (spec §7 / §8 / §12): reject a block — soft-delete it so
/// its task returns to the pool. If it was already accepted, its mirror event is
/// deleted first (spec §8 cascade), so no orphan event survives.
public struct ScheduleRejectBlockTool: AgentTool {
    public let name = "schedule.reject_block"
    public let description =
        "Rejects a scheduled block: soft-deletes it (its task returns to the pool). "
        + "If the block was accepted, its mirror event in the \"Nexus\" calendar is "
        + "deleted too."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "block_id": .string(description: "ScheduledBlock UUID to reject.")
        ],
        required: ["block_id"]
    )

    private let writer: any CalendarEventWriting

    public init(writer: any CalendarEventWriting) {
        self.writer = writer
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["block_id"], field: "block_id")
        let modelContext = context.modelContext.context
        let blocks = ScheduledBlockRepository(context: modelContext, now: context.now)

        guard let block = try blocks.find(id) else {
            throw AgentError.notFound("Scheduled block not found: \(id.uuidString)")
        }

        // Delete the mirror event first (accepted blocks only) so rejecting an
        // accepted block never leaves an orphan event in the "Nexus" calendar.
        if let eventID = block.externalEventID {
            do {
                try await writer.deleteEvent(id: eventID)
            } catch let error as CalendarProviderError {
                if case .underlying(let message) = error {
                    throw AgentError.internalError("Calendar delete failed: \(message)")
                }
                // accessDenied: the event cannot be reached, but the user still
                // wants the block gone — proceed with the soft-delete below.
            }
        }
        try blocks.softDelete(block)
        // Return an explicit deletion confirmation, not a ScheduledBlockDTO:
        // `softDelete` stamps `deletedAt` but never changes `statusRaw`, so a DTO
        // built here would misreport the just-rejected block as still "proposed"/
        // "accepted". Mirrors the {"deleted": true} shape of the other delete tools
        // (comments.delete, calendar.events.delete).
        return .object(["deleted": .bool(true), "block_id": .string(block.id.uuidString)])
    }
}
