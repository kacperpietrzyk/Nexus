import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

#if os(macOS)

/// Pill accent per linked-item kind — the spec's "kind pills" use the DS
/// accent ramp; the mapping is fixed so a kind always reads the same color.
private func kindColor(_ kind: ItemKind) -> Color {
    switch kind {
    case .note: return DS.ColorToken.accentAmber
    case .task: return DS.ColorToken.accentBlue
    case .project: return DS.ColorToken.accentPurple
    case .person: return DS.ColorToken.accentGreen
    case .meeting: return DS.ColorToken.accentCyan
    default: return DS.ColorToken.statusNeutral
    }
}

/// The knowledge cards embedded in the right inspector `MeetingActionsInspector`.
/// Exposed as two focused sections so the inspector can place them at distinct
/// positions in the panel IA (People high, Related low).
///
/// Not rendered as a whole `View` — the inspector instantiates it twice to
/// access the two section properties individually, with `insightsCard` placed
/// between them. `body` is intentionally removed to prevent misuse.
@MainActor
struct KnowledgeSections {

    let model: LiquidMeetingsModel
    let composition: MeetingsComposition
    let router: MeetingNavigationRouter
    let navigation: LiquidMeetingsNavigation
    /// Called when the user taps "Assign" on an unassigned speaker row.
    /// The argument is the raw speaker ID (e.g. `"Speaker_1"`). The inspector
    /// owns the sheet state and presents `RenameSpeakerSheet` from outside this
    /// struct, so `@State` is not needed here.
    var onAssignSpeaker: ((String) -> Void)?

    // MARK: - People section (ANCHOR)

    /// Merged attendees + linked Person contacts into a single "People" card.
    /// Assigned speakers (personID set) show name + link chevron.
    /// Unassigned speakers show the raw label + an "Assign in Transcript" cue.
    /// Always shown (anchor) — renders an empty-state row when there are no
    /// attendees rather than disappearing.
    @ViewBuilder
    var peopleSection: some View {
        LiquidGlassCard("People") {
            let rows = peopleRows
            if rows.isEmpty {
                emptyNote("No participants recorded for this meeting.")
            } else {
                VStack(spacing: DS.Space.xs) {
                    ForEach(rows) { row in
                        personRow(row)
                    }
                }
            }
        }
    }

    /// Merged, deduplicated set of attendees and linked-person items.
    /// Deduplication is by canonical speaker name so that a junk "Participant N"
    /// `Person` entity (created by the V11→V12 backfill) doesn't produce a
    /// second row alongside the unassigned attendee of the same name.
    private var peopleRows: [PersonRow] {
        let linkedPersons = model.linkedItems.filter { $0.kind == .person }
        return dedupedPeopleRows(attendees: model.attendees, linkedPersons: linkedPersons)
    }

    @ViewBuilder
    private func personRow(_ row: PersonRow) -> some View {
        if row.targetID != nil {
            // Assigned person — opens People destination
            Button {
                navigation.openPeople()
            } label: {
                personRowLabel(row: row, showChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.name), assigned to contact")
            .accessibilityHint("Opens People")
        } else if let rawSpeaker = row.rawSpeaker, let onAssignSpeaker {
            // Unassigned speaker — inline Assign button
            HStack(spacing: DS.Space.s) {
                personRowLabel(row: row, showChevron: false)
                Button("Assign") {
                    onAssignSpeaker(rawSpeaker)
                }
                .buttonStyle(.plain)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.accentPrimary)
                .accessibilityHint("Assign this speaker to a contact")
            }
        } else {
            // Unassigned speaker, no assign seam available (linked-person row or no callback)
            HStack(spacing: DS.Space.s) {
                personRowLabel(row: row, showChevron: false)
                Text("Assign in Transcript")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
        }
    }

    private func personRowLabel(row: PersonRow, showChevron: Bool) -> some View {
        HStack(spacing: DS.Space.s) {
            LiquidPill("Person", color: DS.ColorToken.accentGreen)
            Text(row.name)
                .font(DS.FontToken.body)
                .foregroundStyle(
                    row.targetID != nil
                        ? DS.ColorToken.textSecondary : DS.ColorToken.textTertiary
                )
                .lineLimit(1)
            Spacer(minLength: 0)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Related section (empty-hides)

    /// Merged "Related notes" list + Backlinks graph under one "Related" card.
    /// Hidden entirely when both are empty (empty-hides: no card rendered).
    @ViewBuilder
    var relatedSection: some View {
        let hasRelatedNotes = !model.relatedNotes.isEmpty
        let hasBacklinks = !model.graphItems.isEmpty
        if hasRelatedNotes || hasBacklinks {
            LiquidGlassCard("Related") {
                VStack(spacing: DS.Space.m) {
                    if hasRelatedNotes {
                        relatedNotesList
                    }
                    if hasBacklinks {
                        if hasRelatedNotes {
                            Divider()
                                .overlay(DS.ColorToken.strokeHairline)
                        }
                        backlinksGraph
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var relatedNotesList: some View {
        VStack(spacing: DS.Space.xs) {
            ForEach(model.relatedNotes) { note in
                Button {
                    // Notes has no per-note deep-link seam yet; open the Notes destination.
                    navigation.openNotes()
                } label: {
                    HStack(spacing: DS.Space.s) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.ColorToken.accentAmber)
                        Text(note.title)
                            .font(DS.FontToken.body)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var backlinksGraph: some View {
        if let meeting = model.meeting {
            BacklinksGraph(
                centerTitle: meeting.title,
                nodes: model.graphItems,
                onTap: { open($0) }
            )
        }
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .font(DS.FontToken.metadata)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Routing

    /// Routes a linked item to its real destination. Tasks resolve to the
    /// live `TaskItem` and open the app's task detail; notes/people navigate
    /// to their shell destinations (no per-item deep-link seams exist there);
    /// projects select + open the Projects screen; meetings re-route the
    /// meetings router. Kinds without a surface are not rendered (the model
    /// drops them at resolve time).
    private func open(_ item: LiquidMeetingsModel.LinkedItem) {
        switch item.kind {
        case .task:
            let id = item.targetID
            var descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
            descriptor.fetchLimit = 1
            guard let task = try? composition.meetingRepository.context.fetch(descriptor).first
            else { return }
            navigation.openTask(task)
        case .note:
            navigation.openNotes()
        case .project:
            navigation.openProject(item.targetID)
        case .person:
            navigation.openPeople()
        case .meeting:
            router.navigate(to: item.targetID)
        default:
            break
        }
    }
}

// MARK: - Placeholder check (nonisolated copy for use in synchronous contexts)

/// Returns `true` when `name` matches the auto-generated placeholder pattern
/// ("Participant N", "Speaker N", etc.). Mirrors `MeetingPeopleLinker.isNumberedPlaceholder`
/// but is nonisolated so it can be called from synchronous free functions.
private func isPlaceholderName(_ name: String) -> Bool {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return trimmed.range(
        of: "^(participant|speaker)[ _]?\\d+$",
        options: [.regularExpression, .caseInsensitive]
    ) != nil
}

// MARK: - Dedup helper

/// Builds the deduped `[PersonRow]` for the People section.
///
/// Groups attendees and linked `Person` graph items by `canonicalSpeakerKey`.
/// Within each canonical-name group the row is **assigned** (shows chevron)
/// only when there is a real, non-placeholder person link; otherwise it is
/// **unassigned** (shows Assign button).
///
/// This prevents junk "Participant N" `Person` entities (created by the
/// V11→V12 backfill) from generating a second duplicate row alongside the
/// unassigned attendee of the same name.
///
/// Pure function — no store access, no SwiftUI, fully unit-testable.
func dedupedPeopleRows(
    attendees: [LiquidMeetingsModel.Attendee],
    linkedPersons: [LiquidMeetingsModel.LinkedItem]
) -> [PersonRow] {
    // Build a lookup: canonical name → first non-placeholder linked person.
    var linkedByKey: [String: LiquidMeetingsModel.LinkedItem] = [:]
    for item in linkedPersons {
        let key = canonicalSpeakerKey(item.title)
        guard linkedByKey[key] == nil else { continue }
        // Only count it as a real assignment when the name is not a numbered placeholder.
        if !isPlaceholderName(item.title) {
            linkedByKey[key] = item
        }
    }

    var result: [PersonRow] = []
    var seenKeys = Set<String>()

    for attendee in attendees {
        let key = canonicalSpeakerKey(attendee.name)
        guard seenKeys.insert(key).inserted else { continue }

        if let personID = attendee.personID, !isPlaceholderName(attendee.name) {
            // Attendee already has a real person assignment in participantsJSON.
            result.append(PersonRow(id: "attendee-\(attendee.id)", name: attendee.name, targetID: personID, rawSpeaker: nil))
        } else if let linked = linkedByKey[key] {
            // Real (non-placeholder) linked person matches this attendee by name.
            result.append(PersonRow(id: "attendee-\(attendee.id)", name: attendee.name, targetID: linked.targetID, rawSpeaker: nil))
        } else {
            // Unassigned — surface the Assign button.
            result.append(PersonRow(id: "attendee-\(attendee.id)", name: attendee.name, targetID: nil, rawSpeaker: attendee.id))
        }
    }

    // Linked persons whose name has no matching attendee (graph-only entries).
    for item in linkedPersons {
        let key = canonicalSpeakerKey(item.title)
        guard seenKeys.insert(key).inserted else { continue }
        result.append(PersonRow(linkedItem: item))
    }

    return result
}

// MARK: - PersonRow

/// A display row in the People section — either an attendee from the transcript
/// or a person linked via the graph.
struct PersonRow: Identifiable {
    let id: String
    let name: String
    /// Set if the attendee was assigned to a `Person` contact (personID) or if
    /// this row comes from a linked-person graph item (targetID). Used to
    /// distinguish "assigned" (shows chevron + openPeople) from "unassigned"
    /// (shows Assign button).
    let targetID: UUID?
    /// The raw speaker ID from the transcript (e.g. `"Speaker_1"`). Non-nil only
    /// for unassigned attendee rows; nil for linked-person graph-only rows.
    let rawSpeaker: String?

    init(id: String, name: String, targetID: UUID?, rawSpeaker: String?) {
        self.id = id
        self.name = name
        self.targetID = targetID
        self.rawSpeaker = rawSpeaker
    }

    init(linkedItem: LiquidMeetingsModel.LinkedItem) {
        self.id = "linked-\(linkedItem.id)"
        self.name = linkedItem.title
        self.targetID = linkedItem.targetID
        self.rawSpeaker = nil
    }
}

/// Collision-safe backlinks graph (spec §Backlinks).
///
/// In-panel **mini** mode: capped at `miniMaxNodes` peripheral nodes; positions
/// computed by `placeNodes(...)` which guarantees no two pill rects overlap and
/// all stay within the card bounds.  The centre node is rendered as a small
/// accent dot to avoid overlapping the peripheral pills.  Tapping any pill
/// navigates directly.  Tapping the "expand" chevron opens the full graph in a
/// popover where all nodes + full-width labels are shown.
///
/// **Full** mode (inside the popover): all nodes, larger canvas, no node cap.
private struct BacklinksGraph: View {

    // MARK: Configuration

    /// Pill dimensions used by the layout helper for the mini-graph.
    private static let miniPillSize = CGSize(width: 88, height: 22)
    /// Maximum number of peripheral nodes shown in the mini-graph.
    private static let miniMaxNodes = 5
    /// Height of the mini-graph card.
    private static let miniHeight: CGFloat = 190
    /// Popover canvas size.
    private static let fullSize = CGSize(width: 360, height: 280)
    /// Pill dimensions for the full graph in the popover.
    private static let fullPillSize = CGSize(width: 120, height: 24)

    let centerTitle: String
    let nodes: [LiquidMeetingsModel.LinkedItem]
    let onTap: (LiquidMeetingsModel.LinkedItem) -> Void

    @State private var showingFullGraph = false

    // MARK: - Body

    var body: some View {
        miniGraph
            .popover(isPresented: $showingFullGraph) {
                fullGraphPopover
            }
    }

    // MARK: - Mini-graph (collision-safe)

    @ViewBuilder
    private var miniGraph: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let rects = placeNodes(
                nodes.count,
                in: size,
                pillSize: Self.miniPillSize,
                maxNodes: Self.miniMaxNodes
            )
            // Only render as many nodes as we placed rects for.
            let visibleNodes = Array(nodes.prefix(rects.count))

            ZStack {
                // Lines from centre to each peripheral node centre.
                Canvas { context, _ in
                    for rect in rects {
                        let nodeCenter = CGPoint(x: rect.midX, y: rect.midY)
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: nodeCenter)
                        context.stroke(
                            path, with: .color(DS.ColorToken.strokeStrong), lineWidth: 1)
                    }
                }

                // Peripheral node pills.
                ForEach(Array(zip(visibleNodes, rects)), id: \.0.id) { node, rect in
                    Button {
                        onTap(node)
                    } label: {
                        nodePill(
                            node.title,
                            color: kindColor(node.kind),
                            emphasized: false,
                            pillSize: Self.miniPillSize
                        )
                    }
                    .buttonStyle(.plain)
                    .position(CGPoint(x: rect.midX, y: rect.midY))
                    .accessibilityLabel("\(node.kind.displayName): \(node.title)")
                }

                // Centre node — small accent dot to avoid pill-on-pill collision.
                Circle()
                    .fill(DS.ColorToken.accentPrimary)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle().stroke(DS.ColorToken.accentPrimary.opacity(0.4), lineWidth: 2)
                    }
                    .position(center)
                    .accessibilityLabel(centerTitle)
                    .accessibilityHint("Meeting centre node")

                // Expand button — bottom-trailing corner.
                Button {
                    showingFullGraph = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.ColorToken.textMuted)
                        .padding(4)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(DS.ColorToken.glassStrong)
                        }
                }
                .buttonStyle(.plain)
                .position(
                    CGPoint(x: size.width - 14, y: size.height - 14)
                )
                .accessibilityLabel("Expand backlinks graph")
            }
        }
        .frame(height: Self.miniHeight)
    }

    // MARK: - Full-graph popover

    private var fullGraphPopover: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Text("Backlinks")
                    .font(DS.FontToken.caption.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.textSecondary)
                Spacer(minLength: 0)
                Button {
                    showingFullGraph = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.bottom, DS.Space.xxs)

            fullGraphCanvas
        }
        .padding(DS.Space.m)
        .frame(width: Self.fullSize.width)
    }

    @ViewBuilder
    private var fullGraphCanvas: some View {
        let size = Self.fullSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let rects = placeNodes(
            nodes.count,
            in: size,
            pillSize: Self.fullPillSize,
            maxNodes: nodes.count,  // show all in the full view
            centerClear: Self.fullPillSize  // reserve space for the centre pill
        )
        let visibleNodes = Array(nodes.prefix(rects.count))

        ZStack {
            Canvas { context, _ in
                for rect in rects {
                    let nodeCenter = CGPoint(x: rect.midX, y: rect.midY)
                    var path = Path()
                    path.move(to: center)
                    path.addLine(to: nodeCenter)
                    context.stroke(
                        path, with: .color(DS.ColorToken.strokeStrong), lineWidth: 1)
                }
            }

            ForEach(Array(zip(visibleNodes, rects)), id: \.0.id) { node, rect in
                Button {
                    onTap(node)
                    showingFullGraph = false
                } label: {
                    nodePill(
                        node.title,
                        color: kindColor(node.kind),
                        emphasized: false,
                        pillSize: Self.fullPillSize
                    )
                }
                .buttonStyle(.plain)
                .position(CGPoint(x: rect.midX, y: rect.midY))
                .accessibilityLabel("\(node.kind.displayName): \(node.title)")
            }

            // Centre pill — full label, room in the popover.
            nodePill(
                centerTitle,
                color: DS.ColorToken.accentPrimary,
                emphasized: true,
                pillSize: Self.fullPillSize
            )
            .position(center)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Pill

    private func nodePill(
        _ title: String, color: Color, emphasized: Bool, pillSize: CGSize
    ) -> some View {
        Text(title)
            .font(emphasized ? DS.FontToken.caption.weight(.semibold) : DS.FontToken.caption)
            .foregroundStyle(
                emphasized ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary
            )
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .frame(width: pillSize.width, height: pillSize.height)
            .background {
                Capsule(style: .continuous).fill(DS.ColorToken.glassStrong)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(emphasized ? 0.6 : 0.35), lineWidth: 1)
            }
    }
}
#endif
