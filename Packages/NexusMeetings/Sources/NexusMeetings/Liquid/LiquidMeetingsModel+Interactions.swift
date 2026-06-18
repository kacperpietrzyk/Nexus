import Foundation
import NexusCore
import SwiftData

// MARK: - Bulk mutations + summary markdown

extension LiquidMeetingsModel {

    /// Pins every meeting in `ids` to Today (sets `isPinned = true`).
    public func pinAll(_ ids: Set<UUID>, composition: MeetingsComposition) {
        for meetingID in ids {
            guard let meeting = meetings.first(where: { $0.id == meetingID }) else { continue }
            guard !meeting.isPinned else { continue }
            do {
                try composition.meetingRepository.setPinned(meeting, true)
            } catch {
                loadError = String(describing: error)
            }
        }
    }

    /// Soft-deletes every meeting in `ids`. Returns a closure that restores them
    /// (for the undo toast). Meetings that are already deleted are skipped.
    public func deleteAll(
        _ ids: Set<UUID>,
        composition: MeetingsComposition
    ) -> () -> Void {
        // Capture live SwiftData objects before deletion so the undo closure can
        // restore them. `meeting.isPinned` is snapshotted for the restore.
        var deleted: [(Meeting, Bool)] = []
        for meetingID in ids {
            guard let meeting = meetings.first(where: { $0.id == meetingID }) else { continue }
            deleted.append((meeting, meeting.isPinned))
            meeting.deletedAt = Date()
            meeting.updatedAt = Date()
            try? composition.meetingRepository.context.save()
        }
        return {
            for (meeting, wasPinned) in deleted {
                meeting.deletedAt = nil
                meeting.isPinned = wasPinned
                meeting.updatedAt = Date()
                try? composition.meetingRepository.context.save()
            }
        }
    }

    /// Hard-deletes a single meeting (audio + metadata via `MeetingRepository.delete`).
    public func deleteMeeting(_ meeting: Meeting, composition: MeetingsComposition) {
        do {
            try composition.meetingRepository.delete(id: meeting.id)
        } catch {
            loadError = String(describing: error)
        }
    }

    /// Returns the parsed summary body markdown for a meeting (plain string,
    /// no NexusUI dependency) — callers wrap it with `MarkdownExport.entity`.
    public func summaryMarkdownBody(for meeting: Meeting) -> String {
        let sections = MeetingSummarySections.parse(summaryText: meeting.summaryText)
        var parts: [String] = []
        if let overview = sections.overview, !overview.isEmpty {
            parts.append(overview)
        }
        if !sections.decisions.isEmpty {
            let bullets = sections.decisions.map { "- \($0)" }.joined(separator: "\n")
            parts.append("### Decisions\n\n" + bullets)
        }
        for section in sections.extraSections {
            let bullets = section.items.map { "- \($0)" }.joined(separator: "\n")
            parts.append("### \(section.title)\n\n" + bullets)
        }
        return parts.joined(separator: "\n\n")
    }
}
