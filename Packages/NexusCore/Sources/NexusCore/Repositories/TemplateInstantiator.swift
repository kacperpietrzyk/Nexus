import Foundation
import SwiftData

/// Errors thrown by `TemplateInstantiator`.
public enum TemplateInstantiatorError: Error, Equatable {
    /// `instantiate` was called with a task whose `isTemplate == false`.
    case notATemplate(taskID: UUID)
    /// `saveAsTemplate` was called with a task that is already a template.
    case alreadyATemplate(taskID: UUID)
}

/// Deep-copy engine for task templates (Tranche 2 Plan D, spec §4.3).
///
/// Two operations share one copy core:
/// - `saveAsTemplate(_:)` copies a live task (+ subtask tree, links, note
///   content, relative reminders) into an inert `isTemplate == true` blueprint;
/// - `instantiate(_:)` copies a template back into a live task tree.
///
/// Copy rules (locked by the spec):
/// - scalars verbatim; EXCEPT new `id`, `isTemplate` per target, ALL dates nil
///   (`dueAt/startAt/endAt/deadlineAt/snoozedUntil` — v1 has no relative-offset
///   representation, so nothing is "trivially shiftable"), `status = .open`,
///   `lastCompletedAt = nil`, `recurrenceParentId = nil`,
///   `externalSourceID/Metadata = nil`, `cycleID = nil`, fresh timestamps;
/// - `recurrenceRule` verbatim — recurrence activates once an instance gets a
///   due date;
/// - reminders: `.relative` rules and repeating `.absolute` rules — the exact
///   `carriedReminders` filter `makeNextOccurrence` applies;
/// - workflow: nil stays nil (GTD, invariant I7); non-nil resets to `.todo`
///   (the `makeNextOccurrence` precedent — a copy never starts terminal, I1);
/// - note content: per-node copy via `duplicatedNoteRef` (T1 precedent), so
///   editing an instance's note never mutates the template's;
/// - subtasks: recursive recreation with new ids + remapped `parentTaskID`;
/// - links: every copied node's outgoing `Link` rows are re-created from the
///   new ids through `LinkRepository.findOrCreate` (`.labeled` included);
///   intra-tree targets are remapped onto the copied ids; `.scheduledAs` is
///   excluded (occurrence-bound calendar placement, not blueprint).
///
/// Inserts go through `TaskItemRepository.insert` so notifications (none —
/// templates are guarded and instances have no dates), the watch snapshot
/// push, and any repository-level activity hooks behave normally.
@MainActor
public final class TemplateInstantiator {
    private let tasks: TaskItemRepository
    private let links: LinkRepository

    public init(tasks: TaskItemRepository) {
        self.tasks = tasks
        self.links = LinkRepository(context: tasks.context)
    }

    /// Copies `source` (a live, non-template task) into a new inert template tree.
    @discardableResult
    public func saveAsTemplate(_ source: TaskItem) throws -> TaskItem {
        guard !source.isTemplate else {
            throw TemplateInstantiatorError.alreadyATemplate(taskID: source.id)
        }
        return try deepCopy(source, asTemplate: true)
    }

    /// Copies `template` into a new live task tree.
    @discardableResult
    public func instantiate(_ template: TaskItem) throws -> TaskItem {
        guard template.isTemplate else {
            throw TemplateInstantiatorError.notATemplate(taskID: template.id)
        }
        return try deepCopy(template, asTemplate: false)
    }

    // MARK: - Copy core

    private func deepCopy(_ source: TaskItem, asTemplate: Bool) throws -> TaskItem {
        var idMap: [UUID: UUID] = [:]
        let root = try copyTree(source, asTemplate: asTemplate, parentID: nil, idMap: &idMap)
        try recreateOutgoingLinks(idMap: idMap)
        return root
    }

    private func copyTree(
        _ source: TaskItem,
        asTemplate: Bool,
        parentID: UUID?,
        idMap: inout [UUID: UUID]
    ) throws -> TaskItem {
        let copy = try copyNode(source, asTemplate: asTemplate, parentID: parentID)
        try tasks.insert(copy)
        idMap[source.id] = copy.id
        // `allSubtasks` = every live child regardless of status; the copy of a
        // done child starts `.open` like every other node (blueprint semantics).
        // `idMap[child.id] == nil` defends against pre-existing parent cycles.
        for child in try tasks.allSubtasks(of: source) where idMap[child.id] == nil {
            _ = try copyTree(child, asTemplate: asTemplate, parentID: copy.id, idMap: &idMap)
        }
        return copy
    }

    private func copyNode(_ source: TaskItem, asTemplate: Bool, parentID: UUID?) throws -> TaskItem {
        let copy = TaskItem(
            title: source.title,
            body: source.body,
            priority: source.priority,
            status: .open,
            tags: source.tags,
            recurrenceRule: source.recurrenceRule,
            parentTaskID: parentID,
            projectID: source.projectID,
            sectionID: source.sectionID,
            orderIndex: source.orderIndex,
            pinnedAsFocus: source.pinnedAsFocus,
            // GTD nil stays nil (I7); any active machine resets to `.todo`
            // (never terminal — the makeNextOccurrence precedent, I1).
            workflowState: source.workflowState == nil ? nil : .todo,
            assignedAgent: source.agent,
            estimatedDurationSeconds: source.estimatedDurationSeconds,
            durationSource: source.durationSource,
            isTemplate: asTemplate
        )
        // Fresh per-copy note row (T1): editing the copy's note never mutates
        // the source's.
        copy.noteRef = try tasks.duplicatedNoteRef(of: source.noteRef)
        // Carry `.relative` rules and repeating `.absolute` rules — identical
        // to `carriedReminders` in `makeNextOccurrence` (T4): one-shot absolute
        // reminders are occurrence-bound and stay dropped.
        copy.reminders = source.reminders.filter { rule in
            switch rule {
            case .relative:
                return true
            case .absolute(_, let repeats):
                return repeats != nil
            }
        }
        return copy
    }

    private func recreateOutgoingLinks(idMap: [UUID: UUID]) throws {
        for (sourceID, copyID) in idMap {
            for link in try links.outgoing(from: (.task, sourceID)) where link.linkKind != .scheduledAs {
                let target: (ItemKind, UUID)
                if link.toKind == .task, let mappedTarget = idMap[link.toID] {
                    target = (.task, mappedTarget)
                } else {
                    target = (link.toKind, link.toID)
                }
                try links.findOrCreate(
                    from: (.task, copyID),
                    to: target,
                    linkKind: link.linkKind,
                    order: link.order
                )
            }
        }
    }
}
