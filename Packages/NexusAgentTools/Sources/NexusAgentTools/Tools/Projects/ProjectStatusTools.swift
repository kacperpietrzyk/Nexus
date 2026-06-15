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
            "type": .string(
                enumValues: ProjectType.allCases.map(\.rawValue),
                description: "Optional ProjectType. Defaults to generic."
            ),
            "client_id": .string(description: "Optional client Organization UUID."),
            "vendor": .string(description: "Optional vendor/product line."),
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
        let projectType: ProjectType
        if let typeText = try ProjectsToolSupport.optionalTrimmedString(args["type"], field: "type") {
            guard let parsed = ProjectType(rawValue: typeText) else {
                throw AgentError.validation(
                    "Invalid type '\(typeText)'. Expected one of: "
                        + ProjectType.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            projectType = parsed
        } else {
            projectType = .generic
        }
        let clientID = try TasksStructuredCreateArguments.optionalUUID(args["client_id"], field: "client_id")
        // Validate the client/organization FK *before* persisting the project (mirror the
        // parent_project_id check above) — a bad client_id must not leave an orphan project.
        if let clientID {
            _ = try OrganizationsToolSupport.liveOrganization(id: clientID, context: context)
        }
        let vendor = try ProjectsToolSupport.optionalTrimmedString(args["vendor"], field: "vendor")
        let project = try context.projectRepository.create(
            name: name,
            color: glyph,
            parentProjectID: parentID,
            type: projectType
        )
        if let clientID { try context.projectRepository.setClient(clientID, on: project) }
        if let vendor { try context.projectRepository.setVendor(vendor, on: project) }
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

// MARK: - projects.set_stage

public struct ProjectsSetStageTool: AgentTool {
    public let name = "projects.set_stage"
    public let description = """
        Sets a project's granular pipeline stage (must belong to the project's type preset). \
        Also syncs the coarse status. Stage values depend on type: implementation \
        (kickoff…closed), sales (lead…lost), audit (auditPlan…auditReport), internalDev \
        (planning…shipped). Generic projects have no pipeline stages, so this tool always \
        fails on them — use projects.set_status instead.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "stage": .string(
                enumValues: ProjectStage.allCases.map(\.rawValue),
                description: "New ProjectStage (must be in the project type's preset)."
            ),
        ],
        required: ["project_id", "stage"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let stageText = try TasksToolArguments.requiredString(args["stage"], field: "stage")
        guard let stage = ProjectStage(rawValue: stageText) else {
            throw AgentError.validation(
                "Invalid stage '\(stageText)'. Expected one of: "
                    + ProjectStage.allCases.map(\.rawValue).joined(separator: ", ")
            )
        }
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)
        do {
            try context.projectRepository.setStage(stage, on: project)
        } catch let error as ProjectStageError {
            switch error {
            case .stageNotInTypePreset(let stage, let type):
                throw AgentError.validation(
                    "Stage '\(stage.rawValue)' is not valid for project type '\(type.rawValue)'."
                )
            }
        }
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
    public let description = """
        Updates a project's name, glyph, type, client, vendor, or a custom field. \
        Returns the updated project DTO.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "name": .string(description: "Optional new name."),
            "glyph": .string(description: "Optional new achromatic glyph key."),
            "type": .string(enumValues: ProjectType.allCases.map(\.rawValue), description: "Optional new ProjectType."),
            "client_id": .string(description: "Optional client Organization UUID (empty string clears)."),
            "vendor": .string(description: "Optional vendor/product line (empty string clears)."),
            "custom_field_key": .string(description: "Optional custom-field key to set or remove."),
            "custom_field_value": .string(description: "Value for custom_field_key; null/omitted removes the key."),
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
        if let typeText = try ProjectsToolSupport.optionalTrimmedString(args["type"], field: "type") {
            guard let type = ProjectType(rawValue: typeText) else {
                throw AgentError.validation(
                    "Invalid type '\(typeText)'. Expected one of: "
                        + ProjectType.allCases.map(\.rawValue).joined(separator: ", ")
                )
            }
            try context.projectRepository.setType(type, on: project)
        }
        if case .string(let raw)? = args["client_id"] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try context.projectRepository.setClient(nil, on: project)
            } else {
                guard let clientID = UUID(uuidString: trimmed) else {
                    throw AgentError.validation("client_id must be a valid UUID")
                }
                _ = try OrganizationsToolSupport.liveOrganization(id: clientID, context: context)
                try context.projectRepository.setClient(clientID, on: project)
            }
        }
        if case .string(let raw)? = args["vendor"] {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            try context.projectRepository.setVendor(trimmed.isEmpty ? nil : trimmed, on: project)
        }
        if let key = try ProjectsToolSupport.optionalTrimmedString(args["custom_field_key"], field: "custom_field_key") {
            let value: String?
            if case .string(let v)? = args["custom_field_value"] { value = v } else { value = nil }
            try context.projectRepository.setCustomField(key: key, value: value, on: project)
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

// MARK: - projects.sections.list

public struct SectionsListTool: AgentTool {
    public let name = "projects.sections.list"
    public let description = "Lists the ordered sections of a live project."
    public let inputSchema: JSONSchema = .object(
        properties: ["project_id": .string(description: "Project UUID.")],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let projectID = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        _ = try ProjectsToolSupport.liveProject(id: projectID, context: context)
        let sections = try SectionRepository(context: context.modelContext.context, now: context.now)
            .sections(in: projectID)
        return .object(["sections": try TasksToolJSON.encode(sections.map { SectionDTO(from: $0) })])
    }
}

// MARK: - projects.sections.update

public struct SectionsUpdateTool: AgentTool {
    public let name = "projects.sections.update"
    public let description = "Renames a section. Returns the updated section DTO."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "section_id": .string(description: "Section UUID."),
            "name": .string(description: "New section name."),
        ],
        required: ["section_id", "name"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["section_id"], field: "section_id")
        let section = try ProjectsToolSupport.liveSection(id: id, context: context)
        let name = try ProjectsToolSupport.trimmedRequiredString(args["name"], field: "name")
        try SectionRepository(context: context.modelContext.context, now: context.now).rename(section, to: name)
        return try TasksToolJSON.encode(SectionDTO(from: section))
    }
}

// MARK: - projects.sections.delete

public struct SectionsDeleteTool: AgentTool {
    public let name = "projects.sections.delete"
    public let description = """
        Deletes a section. Tasks in it are reassigned to reassign_to_section_id if given, \
        else moved to the project's no-section bucket.
        """
    public let inputSchema: JSONSchema = .object(
        properties: [
            "section_id": .string(description: "Section UUID to delete."),
            "reassign_to_section_id": .string(description: "Optional destination section for its tasks."),
        ],
        required: ["section_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["section_id"], field: "section_id")
        let section = try ProjectsToolSupport.liveSection(id: id, context: context)
        let destination = try TasksStructuredCreateArguments.optionalUUID(
            args["reassign_to_section_id"],
            field: "reassign_to_section_id"
        )
        try SectionRepository(context: context.modelContext.context, now: context.now)
            .delete(section, reassignTasksTo: destination)
        return .object(["id": .string(id.uuidString), "deleted": .bool(true)])
    }
}

// MARK: - projects.sections.reorder

public struct SectionsReorderTool: AgentTool {
    public let name = "projects.sections.reorder"
    public let description = "Moves a section between two siblings (after_section_id / before_section_id)."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "section_id": .string(description: "Section UUID to move."),
            "after_section_id": .string(description: "Optional section it should follow."),
            "before_section_id": .string(description: "Optional section it should precede."),
        ],
        required: ["section_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["section_id"], field: "section_id")
        let section = try ProjectsToolSupport.liveSection(id: id, context: context)
        let afterID = try TasksStructuredCreateArguments.optionalUUID(args["after_section_id"], field: "after_section_id")
        let beforeID = try TasksStructuredCreateArguments.optionalUUID(
            args["before_section_id"],
            field: "before_section_id"
        )
        let after = try afterID.map { try ProjectsToolSupport.liveSection(id: $0, context: context) }
        let before = try beforeID.map { try ProjectsToolSupport.liveSection(id: $0, context: context) }
        try SectionRepository(context: context.modelContext.context, now: context.now)
            .reorder(section, after: after, before: before)
        return try TasksToolJSON.encode(SectionDTO(from: section))
    }
}
