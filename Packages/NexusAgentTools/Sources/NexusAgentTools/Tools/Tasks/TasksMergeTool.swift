import Foundation
import NexusCore
import SwiftData

// MARK: - tasks.merge

/// Merge a duplicate task into a canonical one (dedup). Atomically repoints every
/// graph edge from the duplicate onto the canonical record, unions tags, fills empty
/// fields, carries the earlier `createdAt`, and soft-deletes the duplicate (invariant
/// I2 — no orphaned edges). Mirrors `people.merge` end-to-end for `TaskItem`.
public struct TasksMergeTool: AgentTool {
    public let name = "tasks.merge"
    public let description =
        "Merges a duplicate task (from_id) into a canonical one (into_id): repoints all graph edges, "
        + "unions tags and fills empty fields, then soft-deletes the duplicate. Atomic. Returns the "
        + "surviving canonical task."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "into_id": .string(description: "Canonical Task UUID that survives the merge."),
            "from_id": .string(description: "Duplicate Task UUID that is merged away and soft-deleted."),
        ],
        required: ["into_id", "from_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let intoID = try TasksToolArguments.requiredUUID(args["into_id"], field: "into_id")
        let fromID = try TasksToolArguments.requiredUUID(args["from_id"], field: "from_id")
        let into = try TasksMutationToolSupport.liveTask(id: intoID, context: context)
        let from = try TasksMutationToolSupport.liveTask(id: fromID, context: context)

        do {
            try context.taskRepository.repository.mergeTasks(into: into, from: from)
        } catch let error as TaskMergeError {
            switch error {
            case .cannotMergeIntoSelf:
                throw AgentError.validation("into_id and from_id must be different tasks.")
            case .sourceAlreadyDeleted:
                throw AgentError.conflict("from_id is already deleted.")
            }
        }

        // Re-index: survivor's searchableText changes (merged tags); loser is now a tombstone.
        await context.searchIndex.upsert(IndexedDocument(into))
        await context.searchIndex.remove(kind: .task, id: fromID)

        return try TasksToolJSON.encode(TaskNotesContentStore.dto(for: into, context: context))
    }
}
