import Foundation
import NexusCore

// MARK: - projects.get

public struct ProjectsGetTool: AgentTool {
    public let name = "projects.get"
    public let description = "Fetches one non-deleted project by UUID, including its lifecycle status."
    public let inputSchema: JSONSchema = .object(
        properties: ["project_id": .string(description: "Project UUID to fetch.")],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        return try TasksToolJSON.encode(ProjectDTO(from: project))
    }
}

// MARK: - projects.set_status

public struct ProjectsSetStatusTool: AgentTool {
    public let name = "projects.set_status"
    public let description = """
        Sets a project's lifecycle status. One of: backlog, planned, active, inReview, \
        completed, cancelled. (archivedAt is orthogonal and untouched.)
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "status": .string(
                enumValues: ProjectStatus.allCases.map(\.rawValue),
                description: "New ProjectStatus."
            ),
        ],
        required: ["project_id", "status"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let statusText = try TasksToolArguments.requiredString(args["status"], field: "status")
        guard let status = ProjectStatus(rawValue: statusText) else {
            throw AgentError.validation(
                "Invalid status '\(statusText)'. Expected one of: "
                    + ProjectStatus.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        try context.projectRepository.setStatus(status, on: project)
        return try TasksToolJSON.encode(ProjectDTO(from: project))
    }
}
