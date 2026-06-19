#if os(macOS) || os(iOS)
import SwiftUI
import NexusCore

/// Reusable interactive force-directed knowledge graph. Physics from Grape via
/// `GraphForceLayout`; rendering + interaction are ours (full styling control).
public struct KnowledgeGraphView: View {
    private let snapshot: GraphSnapshot
    private let rootID: GraphNodeID?
    private let style: KnowledgeGraphStyle
    private let onSelect: (GraphNodeID) -> Void

    @State private var basePositions: [GraphNodeID: CGPoint] = [:]
    @State private var dragOverrides: [GraphNodeID: CGPoint] = [:]
    @State private var viewport = GraphViewport()
    @State private var hovered: GraphNodeID?
    // Base values captured at gesture start so onChanged applies the gesture's
    // CUMULATIVE delta against a fixed origin (no per-frame compounding/drift).
    @State private var panBase: CGSize?
    @State private var zoomBase: CGFloat?

    public init(
        snapshot: GraphSnapshot,
        rootID: GraphNodeID?,
        style: KnowledgeGraphStyle,
        onSelect: @escaping (GraphNodeID) -> Void
    ) {
        self.snapshot = snapshot
        self.rootID = rootID
        self.style = style
        self.onSelect = onSelect
    }

    private func world(_ id: GraphNodeID) -> CGPoint { dragOverrides[id] ?? basePositions[id] ?? .zero }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                edgeLayer(size: size)
                ForEach(snapshot.nodes, id: \.nodeID) { node in
                    nodePill(node)
                        .position(viewport.project(world(node.nodeID), in: size))
                        .gesture(nodeDrag(node.nodeID, size: size))
                        #if os(macOS)
                    .onHover { hovered = $0 ? node.nodeID : (hovered == node.nodeID ? nil : hovered) }
                        #endif
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture())
            .gesture(zoomGesture())
            .onAppear { layout(in: size) }
        }
    }

    private func layout(in size: CGSize) {
        let solved = GraphForceLayout.solve(snapshot)
        basePositions = solved
        if let bounds = worldBounds(of: solved) {
            viewport.fit(worldBounds: bounds, in: size, padding: 48)
        }
    }

    private func worldBounds(of positions: [GraphNodeID: CGPoint]) -> CGRect? {
        guard !positions.isEmpty else { return nil }
        let xs = positions.values.map(\.x)
        let ys = positions.values.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    @ViewBuilder private func edgeLayer(size: CGSize) -> some View {
        Canvas { ctx, _ in
            for edge in snapshot.edges {
                let a = viewport.project(world(edge.from), in: size)
                let b = viewport.project(world(edge.to), in: size)
                var path = Path()
                path.move(to: a)
                let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 18)
                path.addQuadCurve(to: b, control: mid)  // gentle curve, not a sad spider
                let incident = hovered == edge.from || hovered == edge.to
                ctx.stroke(
                    path,
                    with: .color(DS.ColorToken.strokeStrong.opacity(incident ? 0.9 : 0.35)),
                    lineWidth: incident ? 1.5 : 1)
            }
        }
    }

    private func nodePill(_ node: GraphNode) -> some View {
        let isRoot = node.nodeID == rootID
        let kindColor = style.color(node.nodeID.kind)
        let dim = hovered != nil && hovered != node.nodeID && !isIncidentToHovered(node.nodeID)
        return HStack(spacing: 4) {
            Image(systemName: style.icon(node.nodeID.kind)).font(.system(size: 10, weight: .medium))
            Text(node.title).font(isRoot ? DS.FontToken.caption.weight(.semibold) : DS.FontToken.caption)
                .lineLimit(1)
        }
        .foregroundStyle(isRoot ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
        .padding(.horizontal, DS.Space.s).padding(.vertical, 5)
        .background { Capsule(style: .continuous).fill(DS.ColorToken.glassStrong) }
        .overlay { Capsule(style: .continuous).stroke(kindColor.opacity(isRoot ? 0.8 : 0.4), lineWidth: isRoot ? 1.5 : 1) }
        .scaleEffect(isRoot ? 1.12 : (1.0 + min(0.25, CGFloat(node.degree) * 0.04)))
        .opacity(dim ? 0.4 : 1)
        .onTapGesture { onSelect(node.nodeID) }
        .accessibilityLabel("\(node.nodeID.kind.rawValue): \(node.title)")
    }

    private func isIncidentToHovered(_ id: GraphNodeID) -> Bool {
        guard let h = hovered else { return false }
        return snapshot.edges.contains { ($0.from == h && $0.to == id) || ($0.to == h && $0.from == id) }
    }

    private func nodeDrag(_ id: GraphNodeID, size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let world = CGPoint(
                    x: (value.location.x - size.width / 2 - viewport.offset.width) / viewport.scale,
                    y: (value.location.y - size.height / 2 - viewport.offset.height) / viewport.scale)
                dragOverrides[id] = world
            }
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                let base = panBase ?? viewport.offset
                if panBase == nil { panBase = base }
                viewport.offset = CGSize(
                    width: base.width + value.translation.width,
                    height: base.height + value.translation.height)
            }
            .onEnded { _ in panBase = nil }
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { v in
                let base = zoomBase ?? viewport.scale
                if zoomBase == nil { zoomBase = base }
                viewport.scale = min(GraphViewport.maxScale, max(GraphViewport.minScale, base * v))
            }
            .onEnded { _ in zoomBase = nil }
    }
}
#endif
