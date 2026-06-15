import Foundation
import NexusCore
import SwiftData

/// `Meeting` joins the anti-lock-in Markdown export (gap-matrix C1). The
/// conformance is what `MarkdownExporter` dispatches on when the apps pass
/// `Meeting.self`; `exportMarkdownDocument(in:)` renders the same document
/// standalone for the per-meeting share affordances (Mac detail pane / iOS
/// detail toolbar).
extension Meeting: MarkdownExportRenderable {

    @MainActor
    public func exportFrontmatterExtras() -> [(String, FrontmatterValue)] {
        MeetingMarkdownRenderer.frontmatterExtras(
            startedAt: startedAt,
            durationSec: durationSec,
            participants: decodedParticipants,
            calendarEventID: calendarEventID
        )
    }

    @MainActor
    public func exportMarkdownBody(in context: ModelContext) -> String {
        MeetingMarkdownRenderer.body(
            summary: MeetingSummarySections.parse(summaryText: summaryText),
            actionItems: Self.actionItemSnapshots(ids: actionItemIDs, context: context),
            segments: (try? MeetingSpeakerSegment.decode(segmentsJSON)) ?? [],
            participants: decodedParticipants,
            transcriptText: transcriptText
        )
    }

    /// Full standalone document for the share surfaces: identical base
    /// frontmatter to the global export, plus the meeting extras and body.
    /// `links` is deliberately empty here — the share sheet ships a single
    /// self-contained file; the global export stays the canonical linked set.
    @MainActor
    public func exportMarkdownDocument(in context: ModelContext) -> String {
        MarkdownDocument(
            id: id,
            kind: kind,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            extraFrontmatter: exportFrontmatterExtras(),
            outgoingLinks: [],
            body: exportMarkdownBody(in: context)
        ).render()
    }

    private var decodedParticipants: [MeetingParticipant] {
        (try? MeetingParticipant.decode(participantsJSON ?? Data())) ?? []
    }

    /// Action items resolved from `actionItemIDs` in stored order, dedup
    /// keep-first — the same shape `LiquidMeetingsModel.actionItems(of:context:)`
    /// uses (synced ids are not unique; CloudKit forbids `@Attribute(.unique)`).
    @MainActor
    private static func actionItemSnapshots(
        ids: [UUID], context: ModelContext
    ) -> [MeetingMarkdownRenderer.ActionItem] {
        guard !ids.isEmpty else { return [] }
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in ids.contains(task.id) && task.deletedAt == nil }
        )
        guard let fetched = try? context.fetch(descriptor) else { return [] }
        let byID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        return ids.compactMap { byID[$0] }.map { task in
            MeetingMarkdownRenderer.ActionItem(
                id: task.id, title: task.title, isDone: task.status == .done)
        }
    }
}
