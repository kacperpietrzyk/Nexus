import Foundation
import NexusCore

/// Pure sentence derivation for audit-log rows (spec §4.1 Rendering). Kept
/// SwiftUI-free so it is testable without a view host — the `CommentsComposer`
/// idiom. Unknown event kinds or payload shapes (synced from a newer build)
/// degrade to generic copy and never crash, mirroring the forward-compat
/// posture of the `workflowState` accessor.
enum ActivityEntryFormatter {

    /// Linear-style sentence for one audit event, e.g. "moved to In Progress".
    /// `projectName` resolves a project UUID to its display name (nil = render
    /// the generic fallback) — injected so the formatter stays context-free.
    static func sentence(
        for entry: ActivityEntry,
        projectName: (UUID) -> String? = { _ in nil }
    ) -> String {
        guard let kind = entry.eventKind else { return "updated" }
        let payload = ActivityChangePayload.decoded(from: entry.payloadJSON)
        switch kind {
        case .created:
            return "created"
        case .completed:
            return "completed"
        case .reopened:
            return "reopened"
        case .deleted:
            return "deleted"
        case .workflowChanged:
            guard let newRaw = payload?.new, let state = WorkflowState(rawValue: newRaw) else {
                return "status changed"
            }
            return "moved to \(workflowDisplayName(state))"
        case .projectMoved:
            guard let newID = payload?.new.flatMap(UUID.init(uuidString:)) else {
                return "removed from project"
            }
            if let name = projectName(newID), !name.isEmpty {
                return "moved to \(name)"
            }
            return "moved to another project"
        case .priorityChanged:
            guard
                let newRaw = payload?.new.flatMap(Int.init),
                let priority = TaskPriority(rawValue: newRaw)
            else {
                return "priority changed"
            }
            return "priority set to \(priorityDisplayName(priority))"
        case .dueChanged:
            guard let newDate = payload?.new.flatMap(ActivityChangePayload.parseDate) else {
                return "due date removed"
            }
            return "due \(newDate.formatted(date: .abbreviated, time: .omitted))"
        case .cycleChanged:
            return payload?.new == nil ? "removed from cycle" : "moved to another cycle"
        }
    }

    /// Same mapping as `TaskDetailInspector+Workflow.workflowLabel` (kept in
    /// sync by the formatter tests; that helper is private to the inspector).
    static func workflowDisplayName(_ state: WorkflowState) -> String {
        switch state {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .done: return "Done"
        case .canceled: return "Canceled"
        case .duplicate: return "Duplicate"
        }
    }

    static func priorityDisplayName(_ priority: TaskPriority) -> String {
        switch priority {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
