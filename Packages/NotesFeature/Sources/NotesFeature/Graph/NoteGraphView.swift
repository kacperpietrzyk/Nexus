import NexusCore
import NexusUI
import SwiftUI

/// Force-directed Canvas visualization of the `Link` graph. The model owns
/// graph assembly and simulation; this view draws positions and forwards
/// gestures/selection.
struct NoteGraphView: View {
    @State private var model: NoteGraphModel
    @State private var transform = GraphViewTransform()
    @State private var dragStartPan: CGSize?
    @State private var magnifyStartZoom: CGFloat?

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
                graphCanvas
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
                iconButton("plus.magnifyingglass", label: "Zoom in") {
                    transform.setZoom(transform.zoom * 1.25)
                }
                iconButton("minus.magnifyingglass", label: "Zoom out") {
                    transform.setZoom(transform.zoom / 1.25)
                }
                iconButton("arrow.counterclockwise", label: "Reset view") {
                    transform = GraphViewTransform()
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

    private var graphCanvas: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: model.isSettled)) { timeline in
                ZStack(alignment: .bottomLeading) {
                    Canvas { context, size in
                        draw(in: context, size: size)
                    }
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(magnifyGesture)
                    .onTapGesture(count: 1, coordinateSpace: .local) { location in
                        handleTap(at: location, in: proxy.size)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Graph canvas")
                    .accessibilityValue(graphAccessibilityValue)

                    if let node = model.selectedNode {
                        selectionCard(for: node)
                    }
                }
                .onChange(of: timeline.date) {
                    model.tick()
                }
            }
        }
    }

    private var graphAccessibilityValue: String {
        "\(model.snapshot.nodes.count) nodes, \(model.snapshot.edges.count) links"
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let nodes = model.snapshot.nodes
        let positions = model.engine.positions
        guard !nodes.isEmpty, nodes.count == positions.count else { return }

        let points = positions.map { transform.screenPoint(for: $0, in: size) }
        var indexByID: [GraphNodeID: Int] = [:]
        indexByID.reserveCapacity(nodes.count)
        for (index, node) in nodes.enumerated() {
            indexByID[node.nodeID] = index
        }

        drawEdges(in: context, points: points, indexByID: indexByID)
        drawNodes(in: context, nodes: nodes, points: points)
    }

    private func drawEdges(
        in context: GraphicsContext,
        points: [CGPoint],
        indexByID: [GraphNodeID: Int]
    ) {
        var edgePath = Path()
        for edge in model.snapshot.edges {
            guard let from = indexByID[edge.from], let to = indexByID[edge.to] else { continue }
            edgePath.move(to: points[from])
            edgePath.addLine(to: points[to])
        }
        context.stroke(edgePath, with: .color(DS.ColorToken.strokeDefault), lineWidth: 1)
    }

    private func drawNodes(in context: GraphicsContext, nodes: [GraphNode], points: [CGPoint]) {
        let showAllLabels = transform.zoom >= 0.8 || nodes.count <= 40
        for (index, node) in nodes.enumerated() {
            let point = points[index]
            let radius = GraphStyle.nodeRadius(degree: node.degree) * transform.zoom
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            let accent = GraphStyle.accent(for: node.nodeID.kind)

            context.fill(Path(ellipseIn: rect), with: .color(accent.opacity(0.85)))
            drawSelectionRing(for: node, rect: rect, in: context)
            drawNodeGlyph(for: node, radius: radius, point: point, in: context)
            if showAllLabels || node.nodeID == model.selectedNodeID {
                drawLabel(for: node, radius: radius, point: point, in: context)
            }
        }
    }

    private func drawSelectionRing(for node: GraphNode, rect: CGRect, in context: GraphicsContext) {
        guard node.nodeID == model.selectedNodeID else { return }
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
            with: .color(DS.ColorToken.textPrimary),
            lineWidth: 1.5
        )
    }

    private func drawNodeGlyph(
        for node: GraphNode,
        radius: CGFloat,
        point: CGPoint,
        in context: GraphicsContext
    ) {
        guard transform.zoom >= 1.2 else { return }
        context.draw(
            Text(Image(systemName: GraphStyle.glyph(for: node.nodeID.kind)))
                .font(.system(size: max(6, radius * 0.9)))
                .foregroundStyle(DS.ColorToken.backgroundApp),
            at: point
        )
    }

    private func drawLabel(
        for node: GraphNode,
        radius: CGFloat,
        point: CGPoint,
        in context: GraphicsContext
    ) {
        context.draw(
            Text(GraphStyle.displayTitle(node.title))
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textSecondary),
            at: CGPoint(x: point.x, y: point.y + radius + 9)
        )
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
        .liquidGlass(.card, radius: DS.Radius.l)
        .padding(DS.Space.l)
        .accessibilityElement(children: .contain)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartPan == nil { dragStartPan = transform.pan }
                let base = dragStartPan ?? .zero
                transform.pan = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height
                )
            }
            .onEnded { _ in dragStartPan = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyStartZoom == nil { magnifyStartZoom = transform.zoom }
                transform.setZoom((magnifyStartZoom ?? 1) * value.magnification)
            }
            .onEnded { _ in magnifyStartZoom = nil }
    }

    private func handleTap(at location: CGPoint, in size: CGSize) {
        let hit = transform.hitTest(
            location,
            nodeIDs: model.engine.nodeIDs,
            positions: model.engine.positions,
            in: size
        )
        model.select(hit)
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
