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

/// The three knowledge cards embedded in the right inspector
/// `MeetingActionsInspector` can embed the identical sections when the
/// column collapses into the inspector.
struct KnowledgeSections: View {

    let model: LiquidMeetingsModel
    let composition: MeetingsComposition
    @ObservedObject var router: MeetingNavigationRouter
    let navigation: LiquidMeetingsNavigation

    var body: some View {
        VStack(spacing: DS.Space.m) {
            linkedToCard
            relatedNotesCard
            backlinksCard
        }
    }

    // MARK: - Linked to

    @ViewBuilder
    private var linkedToCard: some View {
        LiquidGlassCard("Linked to") {
            if model.linkedItems.isEmpty {
                emptyNote("Nothing linked yet. Links appear as the graph grows.")
            } else {
                VStack(spacing: DS.Space.xs) {
                    ForEach(model.linkedItems) { item in
                        linkedRow(item)
                    }
                }
            }
        }
    }

    private func linkedRow(_ item: LiquidMeetingsModel.LinkedItem) -> some View {
        Button {
            open(item)
        } label: {
            HStack(spacing: DS.Space.s) {
                LiquidPill(item.kind.displayName, color: kindColor(item.kind))
                Text(item.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Related notes

    @ViewBuilder
    private var relatedNotesCard: some View {
        LiquidGlassCard("Related notes") {
            if model.relatedNotes.isEmpty {
                emptyNote("No related notes — none share links with this meeting.")
            } else {
                VStack(spacing: DS.Space.xs) {
                    ForEach(model.relatedNotes) { note in
                        Button {
                            // Notes has no per-note deep-link seam yet; the
                            // honest action is opening the Notes destination.
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
        }
    }

    // MARK: - Backlinks graph

    @ViewBuilder
    private var backlinksCard: some View {
        LiquidGlassCard("Backlinks") {
            if model.graphItems.isEmpty {
                emptyNote("No backlinks yet — this meeting isn't referenced anywhere.")
            } else if let meeting = model.meeting {
                BacklinksGraph(
                    centerTitle: meeting.title,
                    nodes: model.graphItems,
                    onTap: { open($0) }
                )
                .frame(height: 190)
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
