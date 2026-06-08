import Foundation
import NexusCore

// MARK: - projects.create

public struct ProjectsCreateTool: AgentTool {
    public let name = "projects.create"
    public let description = "Creates a project and returns its MCP project DTO."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "name": .string(description: "Project name."),
            "glyph": .string(description: "Optional achromatic glyph key. Defaults to azure."),
            "parent_project_id": .string(description: "Optional parent project UUID."),
        ],
        required: ["name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let glyph = try ProjectsToolSupport.optionalTrimmedString(args["glyph"], field: "glyph") ?? "azure"
        let parentID = try TasksStructuredCreateArguments.optionalUUID(
            args["parent_project_id"],
            field: "parent_project_id"
        )
        if let parentID {
            _ = try ProjectsToolSupport.liveProject(id: parentID, context: context)
        }
        let project = try context.projectRepository.create(name: name, color: glyph, parentProjectID: parentID)
        return try TasksToolJSON.encode(ProjectDTO(from: project))
    }
}

// MARK: - sections.create

public struct SectionsCreateTool: AgentTool {
    public let name = "projects.sections.create"
    public let description = "Creates a section inside a live project and returns its MCP section DTO."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "name": .string(description: "Section name."),
        ],
        required: ["project_id", "name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let projectID = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        _ = try ProjectsToolSupport.liveProject(id: projectID, context: context)
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        let section = try SectionRepository(context: context.modelContext.context, now: context.now).create(
            projectID: projectID,
            name: name
        )
        return try TasksToolJSON.encode(SectionDTO(from: section))
    }
}

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
