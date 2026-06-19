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
    /// Attendees take priority; linked person items whose personID already appears
    /// as an attendee's personID are suppressed (no double row).
    private var peopleRows: [PersonRow] {
        var result: [PersonRow] = []
        var seenPersonIDs = Set<UUID>()

        // Attendees from participantsJSON (speakers the pipeline found)
        for attendee in model.attendees {
            if let pid = attendee.personID {
                guard seenPersonIDs.insert(pid).inserted else { continue }
            }
            result.append(PersonRow(attendee: attendee))
        }

        // Linked Person items from the graph that weren't already surfaced as attendees
        for item in model.linkedItems where item.kind == .person {
            guard seenPersonIDs.insert(item.targetID).inserted else { continue }
            result.append(PersonRow(linkedItem: item))
        }

        return result
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
            .frame(height: 190)
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

// MARK: - PersonRow

/// A display row in the People section — either an attendee from the transcript
/// or a person linked via the graph.
private struct PersonRow: Identifiable {
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

    init(attendee: LiquidMeetingsModel.Attendee) {
        self.id = "attendee-\(attendee.id)"
        self.name = attendee.name
        self.targetID = attendee.personID
        // Expose the raw speakerID only for unassigned speakers so the Assign
        // button can pass it to `assignSpeaker(rawSpeaker:...)`.
        self.rawSpeaker = attendee.personID == nil ? attendee.id : nil
    }

    init(linkedItem: LiquidMeetingsModel.LinkedItem) {
        self.id = "linked-\(linkedItem.id)"
        self.name = linkedItem.title
        self.targetID = linkedItem.targetID
        self.rawSpeaker = nil
    }
}

/// Backlinks mini-graph (spec §Backlinks): central meeting node, 1-hop linked
/// nodes around it, thin 1 px `Canvas` lines, glass node pills. Node taps
/// navigate through the same seams as the list rows.
private struct BacklinksGraph: View {

    let centerTitle: String
    let nodes: [LiquidMeetingsModel.LinkedItem]
    let onTap: (LiquidMeetingsModel.LinkedItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let positions = nodePositions(in: proxy.size)

            ZStack {
                Canvas { context, _ in
                    for position in positions {
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: position)
                        context.stroke(
                            path, with: .color(DS.ColorToken.strokeStrong), lineWidth: 1)
                    }
                }

                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    Button {
                        onTap(node)
                    } label: {
                        nodePill(node.title, color: kindColor(node.kind), emphasized: false)
                    }
                    .buttonStyle(.plain)
                    .position(positions[index])
                    .accessibilityLabel("\(node.kind.displayName): \(node.title)")
                }

                nodePill(centerTitle, color: DS.ColorToken.accentPrimary, emphasized: true)
                    .position(center)
            }
        }
    }

    private func nodePill(_ title: String, color: Color, emphasized: Bool) -> some View {
        Text(title)
            .font(emphasized ? DS.FontToken.caption.weight(.semibold) : DS.FontToken.caption)
            .foregroundStyle(
                emphasized ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary
            )
            .lineLimit(1)
            .padding(.horizontal, DS.Space.s)
            .frame(height: 20)
            .frame(maxWidth: 96)
            .background {
                Capsule(style: .continuous).fill(DS.ColorToken.glassStrong)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(color.opacity(emphasized ? 0.6 : 0.35), lineWidth: 1)
            }
    }

    /// Evenly spreads the 1-hop nodes on an ellipse inset from the card edges.
    private func nodePositions(in size: CGSize) -> [CGPoint] {
        let inset: CGFloat = 52
        let radiusX = max(40, size.width / 2 - inset)
        let radiusY = max(30, size.height / 2 - 18)
        return nodes.indices.map { index in
            let angle = (Double(index) / Double(max(1, nodes.count))) * 2 * .pi - .pi / 2
            return CGPoint(
                x: size.width / 2 + radiusX * CGFloat(cos(angle)),
                y: size.height / 2 + radiusY * CGFloat(sin(angle))
            )
        }
    }
}
#endif
