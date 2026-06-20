import NexusCore
import NexusUI
import SwiftUI

/// The Notes knowledge graph. Assembly/scope/filter/selection live in the model;
/// layout + rendering are delegated to the shared `NexusUI.KnowledgeGraphView`
/// (the one constellation renderer used app-wide). This view owns the chrome:
/// scope/depth controls, kind filters, and the selection card.
struct NoteGraphView: View {
    @State private var model: NoteGraphModel
    @State private var resetToken = 0

    private let onOpenNote: (UUID) -> Void
    private let onClose: () -> Void

    init(
        model: NoteGraphModel,
        onOpenNote: @escaping (UUID) -> Void,
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onOpenNote = onOpenNote
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.snapshot.nodes.isEmpty {
                emptyState
            } else {
                graphArea
            }
        }
        .background(DS.ColorToken.backgroundApp)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.m) {
                Text("Graph")
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                scopeControls
                Spacer(minLength: DS.Space.m)
                if model.snapshot.isTruncated {
                    LiquidPill(
                        "Showing \(model.snapshot.nodes.count) of \(model.snapshot.totalNodeCount)",
                        color: DS.ColorToken.accentAmber
                    )
                    .help("Largest items by connections are shown. Filter kinds to narrow the graph.")
                }
                iconButton("arrow.counterclockwise", label: "Reset view") {
                    resetToken += 1
                }
                iconButton("xmark", label: "Close graph") {
                    onClose()
                }
            }
            kindFilterRow
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.l)
        .padding(.bottom, DS.Space.s)
        .background(DS.ColorToken.glassToolbar)
    }

    /// Local scope anchors the graph on its center (orbital ego layout); global
    /// has no focus, so the shared view falls back to force-directed.
    private var rootID: GraphNodeID? {
        if case .local(let center, _) = model.scope { return center }
        return nil
    }

    private var graphArea: some View {
        ZStack(alignment: .bottomLeading) {
            KnowledgeGraphView(
                snapshot: model.snapshot,
                rootID: rootID,
                style: .standard,
                selectedID: model.selectedNodeID,
                onSelect: { model.select($0) }
            )
            .id(resetToken)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Graph canvas")
            .accessibilityValue(graphAccessibilityValue)

            if let node = model.selectedNode {
                selectionCard(for: node)
            }
        }
    }

    private var graphAccessibilityValue: String {
        "\(model.snapshot.nodes.count) nodes, \(model.snapshot.edges.count) links"
    }

    @ViewBuilder private var scopeControls: some View {
        if case .local(let center, let depth) = model.scope {
            NexusSegmentedControl(
                items: [
                    NexusSegmentedItem(id: 1, label: "Depth 1"),
                    NexusSegmentedItem(id: 2, label: "Depth 2"),
                ],
                selection: Binding(
                    get: { depth },
                    set: { model.setScope(.local(center: center, depth: $0)) }
                )
            )
            .frame(width: 164)
            iconButton("globe", label: "Show global graph") {
                model.setScope(.global)
            }
            .help("Global graph")
        }
    }

    private var kindFilterRow: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(GraphStyle.filterableKinds, id: \.self) { kind in
                kindFilterButton(for: kind)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Graph kind filters")
    }

    private func kindFilterButton(for kind: ItemKind) -> some View {
        let isOn = model.includedKinds.contains(kind)
        return Button {
            model.toggle(kind)
        } label: {
            LiquidPill(kind.displayName, color: GraphStyle.accent(for: kind), filled: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isOn ? "Hide" : "Show") \(kind.displayName) nodes")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
            Text("Link notes, tasks, and projects to grow the graph.")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func selectionCard(for node: GraphNode) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: GraphStyle.glyph(for: node.nodeID.kind))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(GraphStyle.accent(for: node.nodeID.kind))
                    .accessibilityHidden(true)
                Text(node.nodeID.kind.displayName.uppercased())
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                Spacer(minLength: 0)
                iconButton("xmark", label: "Deselect node") {
                    model.select(nil)
                }
            }
            Text(GraphStyle.displayTitle(node.title))
                .font(DS.FontToken.bodyStrong)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .lineLimit(2)
            Text("\(node.degree) connection\(node.degree == 1 ? "" : "s")")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
            if node.nodeID.kind == .note {
                NexusButton(variant: .primary, size: .sm) {
                    onOpenNote(node.nodeID.id)
                } label: {
                    Label("Open Note", systemImage: "arrow.up.right")
                }
            }
        }
        .padding(DS.Space.l)
        .frame(width: 260, alignment: .leading)
        .liquidLightCard(cornerRadius: DS.Radius.l)
        .padding(DS.Space.l)
        .accessibilityElement(children: .contain)
    }

    private func iconButton(
        _ systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        NexusButton(variant: .ghost, size: .iconSm, action: action) {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(label)
    }
}
