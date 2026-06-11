import Foundation
import NexusCore

/// Existence validation for graph-edge endpoints.
///
/// `LinkRepository.findOrCreate` mints a `Link` from raw `(ItemKind, UUID)` pairs,
/// so without this check an edge tool (`blocks.add`, `people.link`, `note.link`,
/// `labels.assign`) would happily create a dangling edge to a hallucinated or
/// typo'd id and still report success — polluting the graph and any aggregate
/// that walks it (A2). Each edge tool runs both of its endpoints through
/// `validateLive` before writing, mirroring `comments.add`'s `validateCommentTarget`.
enum AgentEndpointValidator {
    /// Throws `AgentError.notFound` when `(kind, id)` does not resolve to a live
    /// (non-soft-deleted) item.
    ///
    /// The check is deliberately *additive*: kinds with a NexusCore repository are
    /// existence-checked, every other kind passes through unvalidated so this
    /// never shrinks a tool's accepted target set (e.g. `note.link` accepts any
    /// `ItemKind`). `.meeting` is the notable un-checkable kind — the `Meeting`
    /// entity lives in `NexusMeetings`, which `NexusAgentTools` (NexusCore-only)
    /// does not import (R8-adjacent).
    @MainActor
    static func validateLive(_ kind: ItemKind, _ id: UUID, context: AgentContext) throws {
        switch kind {
        case .task:
            _ = try TasksMutationToolSupport.liveTask(id: id, context: context)
        case .person:
            _ = try PeopleToolSupport.livePerson(id: id, context: context)
        case .project:
            guard let project = try context.projectRepository.find(id: id), project.deletedAt == nil else {
                throw AgentError.notFound("Project not found: \(id.uuidString)")
            }
        case .note:
            guard try context.noteRepository.find(id: id) != nil else {
                throw AgentError.notFound("Note not found: \(id.uuidString)")
            }
        case .label:
            guard let label = try context.labelRepository.find(id: id), label.deletedAt == nil else {
                throw AgentError.notFound("Label not found: \(id.uuidString)")
            }
        case .cycle:
            guard let cycle = try context.cycleRepository.find(id: id), cycle.deletedAt == nil else {
                throw AgentError.notFound("Cycle not found: \(id.uuidString)")
            }
        case .meeting, .section, .savedFilter, .debug, .agentMemory, .scheduledBlock:
            // No NexusCore repository reachable here to existence-check; pass through.
            return
        }
    }
}
