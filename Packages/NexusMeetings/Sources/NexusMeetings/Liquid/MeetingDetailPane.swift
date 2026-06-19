import Foundation
import NexusCore
import NexusUI
import SwiftUI

#if os(macOS)

/// Tabs (spec §Tabs). Only surfaces with a real backend ship: Overview (parsed
/// summary + decisions + action items + notes editor) and Transcript. The
/// mockup's Clips / Attachments / Timeline tabs have no backing data anywhere
/// in the schema — intentionally omitted, no dead tabs.
enum MeetingDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case transcript = "Transcript"

    var id: String { rawValue }
}

/// Meeting detail column (spec §Meeting detail header + §Overview content):
/// breadcrumb, serif title, real metadata, attendees, status badges, then the
/// Overview / Transcript tabs.
struct MeetingDetailPane: View {

    let model: LiquidMeetingsModel
    let composition: MeetingsComposition

    @State private var tab: MeetingDetailTab = .overview
    @State private var summaryExpanded = false
    @State private var summaryCopied = false

    var body: some View {
        if let meeting = model.meeting {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                header(meeting)
                tabStrip
                if tab == .overview {
                    overview(meeting)
                } else {
                    transcript(meeting)
                }
            }
        }
    }

    // MARK: - Header

    private func header(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.xxs) {
                Text("Meetings")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textMuted)
                Text(meeting.title)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .lineLimit(1)
            }

            Text(meeting.title)
                .font(DS.FontToken.displayMedium)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .lineLimit(2)

            HStack(spacing: DS.Space.s) {
                metadataItem(
                    "calendar", LiquidMeetingsFormat.fullDate.string(from: meeting.startedAt))
                metadataItem(
                    "clock",
                    LiquidMeetingsFormat.timeRange(
                        start: meeting.startedAt, durationSec: meeting.durationSec))
                metadataItem(
                    MeetingSourceBadge.systemImage(for: meeting),
                    MeetingSourceBadge.label(for: meeting))
            }

            HStack(spacing: DS.Space.s) {
                attendeesRow
                Spacer(minLength: DS.Space.s)
                ForEach(statusBadges(meeting), id: \.label) { badge in
                    LiquidPill(badge.label, color: badge.color)
                }
                Button {
                    NotificationCenter.default.post(name: MeetingRecordingRequest.startManual, object: nil)
                } label: {
                    Label("Record", systemImage: "record.circle")
                }
                .buttonStyle(.borderless)
                .help("Start a recording by picking a meeting window")
                summaryCopyButton(meeting)
                summaryShareButton(meeting)
                shareButton(meeting)
            }
        }
    }

    private func metadataItem(_ systemImage: String, _ text: String) -> some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
            Text(text)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
    }

    /// Initials avatars ONLY for real named participants (decoded from
    /// `participantsJSON`); meetings without labeled speakers show nothing —
    /// no fabricated people.
    @ViewBuilder
    private var attendeesRow: some View {
        if !model.attendees.isEmpty {
            HStack(spacing: DS.Space.xs) {
                HStack(spacing: -6) {
                    ForEach(model.attendees.prefix(5)) { attendee in
                        AttendeeAvatar(name: attendee.name)
                    }
                }
                Text(attendeeNamesText)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var attendeeNamesText: String {
        let names = model.attendees.map(\.name)
        if names.count <= 3 { return names.joined(separator: ", ") }
        return names.prefix(3).joined(separator: ", ") + " +\(names.count - 3)"
    }

    /// Real-state badges (spec §Meeting detail header): Recorded/Imported from
    /// `detectionSource`, Transcribed from a non-empty transcript, Complete
    /// from `processingStatus == ready`, plus honest Failed / Processing.
    private func statusBadges(_ meeting: Meeting) -> [(label: String, color: Color)] {
        var badges: [(String, Color)] = []
        let source = MeetingDetectionSource(rawValue: meeting.detectionSource)
        badges.append(
            source == .imported
                ? ("Imported", DS.ColorToken.accentCyan) : ("Recorded", DS.ColorToken.accentBlue))
        if !meeting.transcriptText.isEmpty {
            badges.append(("Transcribed", DS.ColorToken.accentPurple))
        }
        let raw = meeting.processingStatus
        if MeetingProcessingStatus.isFailed(raw) {
            badges.append(("Failed", DS.ColorToken.statusDanger))
        } else if raw == MeetingProcessingStatus.ready.rawValue {
            badges.append(("Complete", DS.ColorToken.accentGreen))
        } else if raw == MeetingProcessingStatus.recording.rawValue {
            badges.append(("Recording", DS.ColorToken.statusWarning))
        } else {
            badges.append(("Processing", DS.ColorToken.statusWarning))
        }
        return badges
    }

    // MARK: - Summary actions (Copy / Share)

    /// The plain-text AI summary for Copy/Share — trimmed to avoid trailing
    /// whitespace on the clipboard. Distinct from `exportMarkdownDocument`
    /// which is the full meeting document used by the Markdown share button.
    private var summaryText: String {
        (model.meeting?.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Copy summary" icon button — copies `summaryText` to the clipboard with
    /// a transient checkmark feedback. Only active when summary is non-empty.
    @ViewBuilder
    private func summaryCopyButton(_ meeting: Meeting) -> some View {
        let text = summaryText
        if !text.isEmpty {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                withAnimation(DS.Motion.selection) { summaryCopied = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(DS.Motion.selection) { summaryCopied = false }
                }
            } label: {
                headerIconLabel(
                    systemImage: summaryCopied ? "checkmark" : "doc.on.doc"
                )
            }
            .buttonStyle(.plain)
            .help(summaryCopied ? "Copied" : "Copy summary")
            .onChange(of: meeting.id) { _, _ in summaryCopied = false }
        }
    }

    /// "Share summary" button — presents `NSSharingServicePicker` over the
    /// plain summary text. Only active when summary is non-empty.
    @ViewBuilder
    private func summaryShareButton(_ meeting: Meeting) -> some View {
        let text = summaryText
        if !text.isEmpty {
            ShareLink(item: text) {
                headerIconLabel(systemImage: "text.bubble")
            }
            .buttonStyle(.plain)
            .help("Share summary…")
        }
    }

    private func headerIconLabel(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DS.ColorToken.textSecondary)
            .frame(width: 24, height: 24)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }

    /// System share picker over the full meeting Markdown document (frontmatter
    /// + summary + action items + transcript) — the same `ShareLink` idiom as
    /// the inspector's "Share summary…" (`NSSharingServicePicker` on macOS).
    /// The document is rendered eagerly on header rebuild: pure string work
    /// over already-loaded fields, cheap at single-meeting scale.
    private func shareButton(_ meeting: Meeting) -> some View {
        ShareLink(item: meeting.exportMarkdownDocument(in: composition.meetingRepository.context)) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textSecondary)
                .frame(width: 24, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                        .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share meeting as Markdown")
    }

    // MARK: - Tabs

    private var tabStrip: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(MeetingDetailTab.allCases) { item in
                Button {
                    withAnimation(DS.Motion.selection) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(
                            tab == item ? DS.ColorToken.textPrimary : DS.ColorToken.textTertiary
                        )
                        .padding(.horizontal, DS.Space.m)
                        .frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                .fill(tab == item ? DS.ColorToken.glassSelected : .clear)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
            }
            Spacer()
        }
    }

    // MARK: - Overview

    private func overview(_ meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                summaryCard
                decisionsCard
                actionItemsCard(meeting)
                notesCard(meeting)
            }
            .padding(.bottom, DS.Space.l)
        }
    }

    /// AI Summary card (spec §Overview content): the PARSED overview section
    /// of the real stored summary, clamped to 4 lines with an expand toggle.
    /// Text-heavy screen → slightly increased line height (spec §Visual rules).
    @ViewBuilder
    private var summaryCard: some View {
        LiquidGlassCard("AI Summary") {
            if let overview = model.sections.overview, !overview.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(overview)
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineSpacing(4)
                        .lineLimit(summaryExpanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                    if overview.count > 240 || overview.contains("\n") {
                        Button(summaryExpanded ? "Show less" : "Show more") {
                            withAnimation(DS.Motion.panelReveal) { summaryExpanded.toggle() }
                        }
                        .buttonStyle(.plain)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.accentPrimaryHover)
                    }
                }
            } else {
                LiquidEmptyState(
                    systemImage: "text.alignleft",
                    message: "No summary yet — it appears once processing finishes."
                )
            }
        }
    }

    /// Decisions card: green-check rows from the parsed `## Decisions` section
    /// of the real summary. Summaries without a decisions section honestly
    /// show the empty state.
    @ViewBuilder
    private var decisionsCard: some View {
        LiquidGlassCard("Decisions") {
            if model.sections.decisions.isEmpty {
                LiquidEmptyState(
                    systemImage: "checkmark.seal",
                    message: "No decisions were captured in this meeting's summary."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(Array(model.sections.decisions.enumerated()), id: \.offset) { _, decision in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.ColorToken.accentGreen)
                            Text(decision)
                                .font(DS.FontToken.body)
                                .foregroundStyle(DS.ColorToken.textSecondary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// Action Items card: REAL `TaskItem`s resolved from `actionItemIDs`;
    /// checkbox completes through the task repository. Owner column omitted —
    /// Nexus is single-user by design. Due date shows as row metadata.
    @ViewBuilder
    private func actionItemsCard(_ meeting: Meeting) -> some View {
        LiquidGlassCard("Action Items") {
            if model.actionItems.isEmpty {
                LiquidEmptyState(
                    systemImage: "checklist",
                    message: "No action items were extracted from this meeting."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(model.actionItems, id: \.id) { task in
                        LiquidTaskRow(
                            task.title,
                            isDone: task.status == .done,
                            metadata: task.dueAt.map {
                                LiquidMeetingsFormat.dayAndTime.string(from: $0)
                            },
                            onToggle: { model.toggleActionItem(task, composition: composition) }
                        )
                    }
                }
            }
        }
    }

    /// Notes editor card (spec §Notes editor): re-hosts the EXISTING summary
    /// editor seam (`SummaryView` — view + raw-markdown `TextEditor` persisting
    /// through `MeetingRepository`) on a sunken background per the visual
    /// rules ("keep notes editor darker/sunken than surrounding cards"). No
    /// new rich editor and no NotesFeature import — the meeting's notes ARE
    /// its summary markdown.
    private func notesCard(_ meeting: Meeting) -> some View {
        LiquidGlassCard("Notes") {
            SummaryView(
                meetingID: meeting.id, repository: composition.meetingRepository, style: .liquid
            )
            // Load-bearing identity pin: without it SwiftUI reuses the
            // child's @StateObject across selection changes and keeps
            // showing the first meeting (same fix as MeetingDetailView).
            .id(meeting.id)
            .frame(minHeight: 260)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .fill(DS.ColorToken.backgroundSunken.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                    .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
            }
        }
    }

    // MARK: - Transcript

    /// Existing transcript surface (speaker rows + rename/People linking)
    /// re-hosted in liquid chrome — content unchanged, glass shell new.
    private func transcript(_ meeting: Meeting) -> some View {
        TranscriptView(
            meetingID: meeting.id,
            repository: composition.meetingRepository,
            style: .liquid,
            peopleLinker: composition.peopleLinker,
            personRepository: composition.personRepository,
            attendeeSeedProvider: { await composition.calendarAttendeeCandidates(for: $0) }
        )
        // Same load-bearing identity pin as the notes card.
        .id(meeting.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidLightCard(cornerRadius: DS.Radius.l)
    }
}

/// 24 pt initials avatar for a real participant.
private struct AttendeeAvatar: View {
    let name: String

    var body: some View {
        Text(initials)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(DS.ColorToken.textPrimary)
            .frame(width: 24, height: 24)
            .background {
                Circle().fill(DS.ColorToken.glassStrong)
            }
            .overlay {
                Circle().stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
            }
            .accessibilityLabel(name)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
#endif
