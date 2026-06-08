import Foundation

/// Discriminator stored on every `Linkable` model + on `Link.fromKind`/`toKind`.
/// Stable raw values — these land in CloudKit and must NEVER be renamed without a migration.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case note
    case task
    case meeting
    case project
    case section
    case savedFilter
    case debug
    case agentMemory
    /// A proposed/accepted scheduler time block for a task (Calendar module).
    case scheduledBlock
    /// A structural `Label` entity (Projects tier, spec §4.4). Labels hang off
    /// tasks and projects via the `Link` graph (`LinkKind.labeled`).
    case label

    public var displayName: String {
        switch self {
        case .note: return "Note"
        case .task: return "Task"
        case .meeting: return "Meeting"
        case .project: return "Project"
        case .section: return "Section"
        case .savedFilter: return "Saved Filter"
        case .debug: return "Debug"
        case .agentMemory: return "Agent Memory"
        case .scheduledBlock: return "Scheduled Block"
        case .label: return "Label"
        }
    }
}
