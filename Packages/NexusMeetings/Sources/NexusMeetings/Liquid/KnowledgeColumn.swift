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

/// SF Symbol name for a linked-item kind.  Pure function — no state
/// dependencies — defined once here so `KnowledgeSections` and
/// `RelatedKnowledgeSection` share the same mapping.
private func kindIcon(_ kind: ItemKind) -> String {
    switch kind {
    case .task: return "checklist"
    case .note: return "doc.text"
    case .project: return "folder"
    case .meeting: return "calendar"
    case .person: return "person"
    default: return "circle"
    }
}

// MARK: - Related chips grouping helper

/// Groups knowledge-link items (persons excluded) by kind for the panel.
/// Display order: task, note, project, meeting.
enum RelatedChips {
    static let order: [ItemKind] = [.task, .note, .project, .meeting]

    static func groups(
        _ items: [LiquidMeetingsModel.LinkedItem]
    ) -> [(kind: ItemKind, items: [LiquidMeetingsModel.LinkedItem])] {
        order.compactMap { kind in
            let matches = items.filter { $0.kind == kind }
            return matches.isEmpty ? nil : (kind, matches)
        }
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

    /// Related notes list + grouped chips + knowledge graph sheet, under one
    /// "Related" card. Hidden entirely when both notes and chips are empty.
    @ViewBuilder
    var relatedSection: some View {
        let hasRelatedNotes = !model.relatedNotes.isEmpty
        let chips = RelatedChips.groups(model.graphItems)
        if hasRelatedNotes || !chips.isEmpty {
            LiquidGlassCard("Related") {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if hasRelatedNotes { relatedNotesList }
                    if !chips.isEmpty {
                        if hasRelatedNotes { Divider().overlay(DS.ColorToken.strokeHairline) }
                        RelatedKnowledgeSection(
                            chips: chips,
                            meeting: model.meeting,
                            composition: composition,
                            navigation: navigation,
                            router: router,
                            model: model,
                            onOpen: { open($0) }
                        )
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

// MARK: - Related knowledge section (real View — owns sheet state)

/// A real SwiftUI View so `@State private var showingGraph` persists across
/// `KnowledgeSections` re-instantiation (the parent struct has no `body` and is
/// recreated each render). Renders grouped chips and an "Open graph" button that
/// presents the full `KnowledgeGraphView` sheet.
private struct RelatedKnowledgeSection: View {
    let chips: [(kind: ItemKind, items: [LiquidMeetingsModel.LinkedItem])]
    let meeting: Meeting?
    let composition: MeetingsComposition
    let navigation: LiquidMeetingsNavigation
    let router: MeetingNavigationRouter
    let model: LiquidMeetingsModel
    let onOpen: (LiquidMeetingsModel.LinkedItem) -> Void

    @State private var showingGraph = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            ForEach(chips, id: \.kind) { group in
                Text(group.kind.displayName.uppercased())
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                ForEach(group.items) { item in
                    Button {
                        onOpen(item)
                    } label: {
                        HStack(spacing: DS.Space.s) {
                            Image(systemName: kindIcon(item.kind))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(kindColor(item.kind))
                            Text(item.title)
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

            if let meeting {
                Button {
                    showingGraph = true
                } label: {
                    Label("Open graph", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(DS.FontToken.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.ColorToken.accentPrimary)
                .knowledgeGraphSheet(
                    isPresented: $showingGraph,
                    rootID: GraphNodeID(.meeting, meeting.id),
                    style: KnowledgeGraphStyle(color: kindColor, icon: kindIcon),
                    header: meeting.title,
                    initialDepth: 1, maxDepth: 2,
                    snapshotForDepth: { depth in
                        model.knowledgeGraphSnapshot(
                            composition: composition, depth: depth,
                            isPlaceholder: { id, name in
                                id.kind == .person && isPlaceholderName(name)
                            }
                        )
                    },
                    onSelect: { openGraphNode($0) }
                )
            }
        }
    }

    private func openGraphNode(_ node: GraphNodeID) {
        switch node.kind {
        case .task:
            let id = node.id
            var descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { $0.id == id && $0.deletedAt == nil })
            descriptor.fetchLimit = 1
            guard let task = try? composition.meetingRepository.context.fetch(descriptor).first
            else { return }
            navigation.openTask(task)
        case .note:
            navigation.openNotes()
        case .project:
            navigation.openProject(node.id)
        case .person:
            navigation.openPeople()
        case .meeting:
            router.navigate(to: node.id)
        default:
            break
        }
    }
}
#endif
