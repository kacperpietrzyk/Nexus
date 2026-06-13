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
        let sectionRepository = SectionRepository(context: context.modelContext.context, now: context.now)
        let sections = try sectionRepository.sections(in: project.id)
        let tasks = try context.taskRepository.repository.tasks(in: project.id)
        return try TasksToolJSON.encode(ProjectDTO(from: project, sections: sections, taskCount: tasks.count))
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

// MARK: - projects.list

public struct ProjectsListTool: AgentTool {
    public let name = "projects.list"
    public let description = "Lists active (non-deleted, non-archived) projects, optionally filtered by status."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "status": .string(
                enumValues: ProjectStatus.allCases.map(\.rawValue),
                description: "Optional ProjectStatus filter."
            )
        ],
        required: []
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        var projects = try context.projectRepository.allActive()
        if let statusText = args["status"]?.stringValue {
            guard let status = ProjectStatus(rawValue: statusText) else {
                throw AgentError.validation(
                    "Invalid status '\(statusText)'. Expected one of: "
                        + ProjectStatus.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            projects = projects.filter { $0.status == status }
        }
        return .object(["projects": try TasksToolJSON.encode(projects.map { ProjectDTO(from: $0) })])
    }
}

// MARK: - projects.update

public struct ProjectsUpdateTool: AgentTool {
    public let name = "projects.update"
    public let description = "Renames and/or recolors (glyph) a project. Returns the updated project DTO."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "name": .string(description: "Optional new name."),
            "glyph": .string(description: "Optional new achromatic glyph key."),
        ],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        if let name = try ProjectsToolSupport.optionalTrimmedString(args["name"], field: "name") {
            try context.projectRepository.rename(project, to: name)
        }
        if let glyph = try ProjectsToolSupport.optionalTrimmedString(args["glyph"], field: "glyph") {
            try context.projectRepository.recolor(project, to: glyph)
        }
        return try TasksToolJSON.encode(ProjectDTO(from: project))
    }
}

// MARK: - projects.archive

public struct ProjectsArchiveTool: AgentTool {
    public let name = "projects.archive"
    public let description = "Archives a project (and its sub-projects). Returns the updated project DTO."
    public let inputSchema: JSONSchema = .object(
        properties: ["project_id": .string(description: "Project UUID.")],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        try context.projectRepository.archive(project)
        return try TasksToolJSON.encode(ProjectDTO(from: project))
    }
}

// MARK: - projects.unarchive

public struct ProjectsUnarchiveTool: AgentTool {
    public let name = "projects.unarchive"
    public let description = "Unarchives a project. Returns the updated project DTO."
    public let inputSchema: JSONSchema = .object(
        properties: ["project_id": .string(description: "Project UUID.")],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        try context.projectRepository.unarchive(project)
        return try TasksToolJSON.encode(ProjectDTO(from: project))
    }
}

// MARK: - projects.delete

public struct ProjectsDeleteTool: AgentTool {
    public let name = "projects.delete"
    public let description = "Soft-deletes a project and cascades to its sub-projects. Returns {id, deleted}."
    public let inputSchema: JSONSchema = .object(
        properties: ["project_id": .string(description: "Project UUID.")],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        try context.projectRepository.softDelete(project, cascade: true)
        return .object(["id": .string(id.uuidString), "deleted": .bool(true)])
    }
}
