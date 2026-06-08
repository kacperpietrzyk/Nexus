import Foundation
import NexusCore
import SwiftData

/// Shared helpers for the Projects-tier MCP tools (spec §10). Endpoint resolution
/// for labels/blocks mirrors the comments tools' `(UUID, ItemKind)` parsing.
enum ProjectsToolSupport {
    /// Resolves a live (non-soft-deleted) `Project` by UUID, throwing `notFound`.
    @MainActor
    static func liveProject(id: UUID, context: AgentContext) throws -> Project {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { project in
                project.id == id && project.deletedAt == nil
            }
        )
        guard let project = try context.modelContext.context.fetch(descriptor).first else {
            throw AgentError.notFound("Project not found: \(id.uuidString)")
        }
        return project
    }

    /// Parses an `item_id` + `item_kind` pair restricted to task/project endpoints
    /// (the only valid `.labeled`/`.blocks` endpoints in scope).
    static func parseEndpoint(_ args: JSONValue) throws -> (UUID, LabelEndpointKind) {
        guard let idText = args["item_id"]?.stringValue, let id = UUID(uuidString: idText) else {
            throw AgentError.validation("item_id must be a valid UUID")
        }
        guard let kindText = args["item_kind"]?.stringValue else {
            throw AgentError.validation("item_kind must be 'task' or 'project'")
        }
        switch kindText {
        case "task": return (id, .task)
        case "project": return (id, .project)
        default: throw AgentError.validation("item_kind must be 'task' or 'project'")
        }
    }
}

extension LabelEndpointKind {
    /// The `ItemKind` this endpoint maps onto in the `Link` graph.
    var endpointItemKind: ItemKind {
        switch self {
        case .task: return .task
        case .project: return .project
        }
    }
}
