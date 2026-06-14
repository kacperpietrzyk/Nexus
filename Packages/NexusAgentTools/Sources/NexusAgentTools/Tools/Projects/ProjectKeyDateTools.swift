import Foundation
import NexusCore

// MARK: - projects.set_key_date

/// Creates or updates a project anchor key date (upsert keyed on projectID + anchorKey).
public struct ProjectsSetKeyDateTool: AgentTool {
    public let name = "projects.set_key_date"
    public let description =
        "Creates or updates a key date anchor for a project (upsert keyed on anchor_key). "
        + "Returns the stored key date fields."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "anchor_key": .string(description: "Short mnemonic key (e.g. 'T0', 'PO', 'KICK')."),
            "label": .string(description: "Human-readable label for the anchor date."),
            "date": .string(description: "ISO8601 date/timestamp for this anchor."),
            "is_contractual": .boolean(description: "Whether this date is contractually binding (default false)."),
        ],
        required: ["project_id", "anchor_key", "label", "date"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let projectID = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        _ = try ProjectsToolSupport.liveProject(id: projectID, context: context)
        let anchorKey = try ProjectsToolSupport.trimmedRequiredString(args["anchor_key"], field: "anchor_key")
        let label = try ProjectsToolSupport.trimmedRequiredString(args["label"], field: "label")
        let date = try ProjectKeyDateTools.requiredDate(args["date"], field: "date")
        let isContractual = args["is_contractual"]?.boolValue ?? false

        let keyDate = try context.projectKeyDateRepository.setKeyDate(
            projectID: projectID,
            anchorKey: anchorKey,
            label: label,
            date: date,
            isContractual: isContractual
        )
        return ProjectKeyDateTools.encode(keyDate)
    }
}

// MARK: - projects.list_key_dates

/// Lists all key dates for a project, sorted by date ascending.
public struct ProjectsListKeyDatesTool: AgentTool {
    public let name = "projects.list_key_dates"
    public let description =
        "Lists all key date anchors for a project, sorted by date ascending. "
        + "Returns an array under 'key_dates'."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID.")
        ],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let projectID = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        _ = try ProjectsToolSupport.liveProject(id: projectID, context: context)
        // list() already returns date-ascending sorted results (sorted in the repo)
        let keyDates = try context.projectKeyDateRepository.list(projectID: projectID)
        return .object(["key_dates": .array(keyDates.map { ProjectKeyDateTools.encode($0) })])
    }
}

// MARK: - projects.delete_key_date

/// Soft-deletes a key date anchor identified by (project_id, anchor_key).
public struct ProjectsDeleteKeyDateTool: AgentTool {
    public let name = "projects.delete_key_date"
    public let description =
        "Soft-deletes the key date anchor identified by anchor_key within a project. "
        + "No-ops if the anchor does not exist."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID."),
            "anchor_key": .string(description: "Anchor key to delete."),
        ],
        required: ["project_id", "anchor_key"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let projectID = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        _ = try ProjectsToolSupport.liveProject(id: projectID, context: context)
        let anchorKey = try ProjectsToolSupport.trimmedRequiredString(args["anchor_key"], field: "anchor_key")
        try context.projectKeyDateRepository.delete(projectID: projectID, anchorKey: anchorKey)
        return .object(["ok": .bool(true)])
    }
}

// MARK: - Shared helpers

enum ProjectKeyDateTools {
    /// Shared output formatter. `ISO8601DateFormatter` is expensive to construct, and
    /// `list_key_dates` encodes N rows per call — a single reused instance avoids that
    /// churn. `nonisolated(unsafe)` is safe: the formatter is configured once and only
    /// read thereafter (`string(from:)` on a fixed-options ISO8601 formatter is
    /// thread-safe in practice; matches `NoteDTO.isoFormatter`).
    nonisolated(unsafe) private static let outputFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Parses a required ISO8601 date argument.
    static func requiredDate(_ value: JSONValue?, field: String) throws -> Date {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required ISO8601 date field: \(field)")
        }
        guard let date = TasksMutationToolSupport.parseISO8601(text) else {
            throw AgentError.validation("Invalid ISO8601 timestamp for field: \(field)")
        }
        return date
    }

    /// Encodes a `ProjectKeyDate` to a `JSONValue` object. The returned shape
    /// intentionally omits the row `id` and `project_id`: the agent identifies a key
    /// date by `(project_id, anchor_key)` (the upsert key it already knows), and the
    /// plan spec defines this minimal DTO. `date` is always emitted with fractional
    /// seconds, so a round-tripped input may gain `.000` — semantically identical.
    static func encode(_ kd: ProjectKeyDate) -> JSONValue {
        .object([
            "anchor_key": .string(kd.anchorKey),
            "label": .string(kd.label),
            "date": .string(outputFormatter.string(from: kd.date)),
            "is_contractual": .bool(kd.isContractual),
        ])
    }
}
