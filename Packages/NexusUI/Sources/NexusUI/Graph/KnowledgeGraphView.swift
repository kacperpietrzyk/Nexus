#if os(macOS) || os(iOS)
import SwiftUI
import NexusCore

/// Reusable interactive knowledge graph rendered as a constellation: luminous
/// orbs in aurora space, gradient filaments between them, the focus node pinned
/// dead-centre. Physics from Grape via `GraphForceLayout`; the look lives in
/// `ConstellationRenderer`. One Canvas draws everything (scales to the 300-node
/// cap), so both the Meetings sheet and the Notes graph share one renderer.
public struct KnowledgeGraphView: View {
    private let snapshot: GraphSnapshot
    private let rootID: GraphNodeID?
    private let style: KnowledgeGraphStyle
    private let selectedID: GraphNodeID?
    private let onSelect: (GraphNodeID) -> Void

    @State private var positions: [GraphNodeID: CGPoint] = [:]
    @State private var viewport = GraphViewport()
    @State private var hovered: GraphNodeID?
    @State private var appeared = false
    @State private var panBase: CGSize?
    @State private var zoomBase: CGFloat?

    public init(
        snapshot: GraphSnapshot,
        rootID: GraphNodeID?,
        style: KnowledgeGraphStyle,
        selectedID: GraphNodeID? = nil,
        onSelect: @escaping (GraphNodeID) -> Void
    ) {
        self.snapshot = snapshot
        self.rootID = rootID
        self.style = style
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                depthBackground(size: size)
                TimelineView(.animation(paused: snapshot.nodes.count > 60)) { timeline in
                    Canvas { context, canvasSize in
                        draw(
                            context, size: canvasSize,
                            time: timeline.date.timeIntervalSinceReferenceDate)
                    }
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.97)
                }
            }
            .contentShape(Rectangle())
            .gesture(panGesture())
            .gesture(zoomGesture())
            .onTapGesture(count: 1, coordinateSpace: .local) { location in
                if let hit = hitTest(location, in: size) { onSelect(hit) }
            }
            #if os(macOS)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location): hovered = hitTest(location, in: size)
                case .ended: hovered = nil
                }
            }
            #endif
            .onAppear {
                layout(in: size)
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
            // Filter / scope / depth changes hand us a fresh snapshot — re-solve so
            // new nodes get positions instead of collapsing onto the origin.
            .onChange(of: snapshot) { layout(in: size) }
        }
    }

    /// Atmospheric field: deep base + a few soft accent auroras + a vignette so
    /// the constellation sits in space, not a flat black void.
    private func depthBackground(size: CGSize) -> some View {
        ZStack {
            DS.ColorToken.backgroundSunken
            AuroraBlob(
                color: DS.ColorToken.accentAmber, opacity: 0.13, diameter: size.height * 1.1,
                position: CGPoint(x: size.width * 0.30, y: size.height * 0.34))
            AuroraBlob(
                color: DS.ColorToken.accentBlue, opacity: 0.11, diameter: size.height * 1.3,
                position: CGPoint(x: size.width * 0.74, y: size.height * 0.70))
            AuroraBlob(
                color: DS.ColorToken.accentPurple, opacity: 0.09, diameter: size.height * 0.9,
                position: CGPoint(x: size.width * 0.60, y: size.height * 0.10))
            RadialGradient(
                colors: [.clear, DS.ColorToken.backgroundSunken.opacity(0.7)],
                center: .center, startRadius: size.height * 0.16, endRadius: size.height * 0.92)
        }
        .allowsHitTesting(false)
    }

    // MARK: Drawing

    private func draw(_ context: GraphicsContext, size: CGSize, time: Double) {
        guard !snapshot.nodes.isEmpty else { return }
        let pulse = (sin(time * 1.7) + 1) / 2  // 0…1, slow breath for the focus halo
        var screen: [GraphNodeID: CGPoint] = [:]
        screen.reserveCapacity(snapshot.nodes.count)
        for node in snapshot.nodes {
            screen[node.nodeID] = viewport.project(positions[node.nodeID] ?? .zero, in: size)
        }
        let active = hovered ?? selectedID

        // Pass 1 — filaments under everything.
        for edge in snapshot.edges {
            guard let from = screen[edge.from], let toPoint = screen[edge.to] else { continue }
            let emphasized = active != nil && (edge.from == active || edge.to == active)
            let dimmed = active != nil && !emphasized
            ConstellationRenderer.drawEdge(
                context, from: from, to: toPoint,
                colorStart: style.color(edge.from.kind), colorEnd: style.color(edge.to.kind),
                emphasized: emphasized, dimmed: dimmed)
        }

        // Pass 2 — halos.
        for node in snapshot.nodes {
            guard let point = screen[node.nodeID] else { continue }
            let isFocus = node.nodeID == rootID
            let dimmed = active != nil && !isActiveOrIncident(node.nodeID, to: active)
            let intensity: Double =
                dimmed
                ? 0.3
                : isFocus
                    ? (1.05 + 0.4 * pulse)
                    : (node.nodeID == active ? 1.2 : 0.85)
            ConstellationRenderer.drawHalo(
                context, at: point, radius: radius(node), color: style.color(node.nodeID.kind),
                intensity: intensity)
        }

        // Pass 3 — orb bodies.
        for node in snapshot.nodes {
            guard let point = screen[node.nodeID] else { continue }
            let isFocus = node.nodeID == rootID
            let dimmed = active != nil && !isActiveOrIncident(node.nodeID, to: active)
            let showGlyph = isFocus || node.degree >= 6
            ConstellationRenderer.drawCore(
                context, at: point, radius: radius(node), color: style.color(node.nodeID.kind),
                isFocus: isFocus, isSelected: node.nodeID == selectedID, dimmed: dimmed,
                glyph: showGlyph ? style.icon(node.nodeID.kind) : nil)
        }

        // Pass 4 — labels (density-gated, on top).
        for node in snapshot.nodes {
            guard let point = screen[node.nodeID], shouldLabel(node, active: active) else { continue }
            let emphasized = node.nodeID == rootID || node.nodeID == active || node.nodeID == selectedID
            let topOffset = radius(node) + (node.nodeID == rootID ? 13 : 8)
            ConstellationRenderer.drawLabel(
                context, at: point, topOffset: topOffset, title: node.title, emphasized: emphasized)
        }
    }

    private func radius(_ node: GraphNode) -> CGFloat {
        ConstellationRenderer.nodeRadius(degree: node.degree, isFocus: node.nodeID == rootID)
    }

    private func shouldLabel(_ node: GraphNode, active: GraphNodeID?) -> Bool {
        if node.nodeID == rootID || node.nodeID == selectedID || node.nodeID == active { return true }
        if isActiveOrIncident(node.nodeID, to: active), active != nil { return true }
        if snapshot.nodes.count <= 24 { return true }
        if viewport.scale >= 1.3 { return true }
        return node.degree >= 5
    }

    private func isActiveOrIncident(_ id: GraphNodeID, to active: GraphNodeID?) -> Bool {
        guard let active else { return false }
        if id == active { return true }
        return snapshot.edges.contains {
            ($0.from == active && $0.to == id) || ($0.to == active && $0.from == id)
        }
    }

    // MARK: Layout

    private func layout(in size: CGSize) {
        // Ego/local graph → intentional orbital rings; global map → organic force.
        let hasRoot = rootID.map { id in snapshot.nodes.contains { $0.nodeID == id } } ?? false
        let solved: [GraphNodeID: CGPoint]
        if let rootID, hasRoot {
            solved = RadialEgoLayout.solve(snapshot, rootID: rootID)
        } else {
            solved = GraphForceLayout.solve(snapshot)
        }
        positions = solved
        let points = Array(solved.values)
        if let rootID, let focus = solved[rootID] {
            viewport.fitFocused(on: focus, points: points, in: size, padding: 96)
        } else if let bounds = worldBounds(of: points) {
            viewport.fit(worldBounds: bounds, in: size, padding: 72)
        }
    }

    private func worldBounds(of points: [CGPoint]) -> CGRect? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
            let minY = ys.min(), let maxY = ys.max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func hitTest(_ location: CGPoint, in size: CGSize) -> GraphNodeID? {
        var best: GraphNodeID?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for node in snapshot.nodes {
            let point = viewport.project(positions[node.nodeID] ?? .zero, in: size)
            let distance = hypot(location.x - point.x, location.y - point.y)
            if distance <= radius(node) + 9, distance < bestDistance {
                bestDistance = distance
                best = node.nodeID
            }
        }
        return best
    }

    // MARK: Gestures

    private func panGesture() -> some Gesture {
        DragGesture(minimumDistance: 2)
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
            .onChanged { value in
                let base = zoomBase ?? viewport.scale
                if zoomBase == nil { zoomBase = base }
                viewport.scale = min(
                    GraphViewport.maxScale,
                    max(GraphViewport.minScale, base * value))
            }
            .onEnded { _ in zoomBase = nil }
    }
}

/// A single soft accent aurora behind the constellation. A view (not a helper
/// func) so the long signature stays clear of the format↔lint brace conflict.
private struct AuroraBlob: View {
    let color: Color
    let opacity: Double
    let diameter: CGFloat
    let position: CGPoint

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), .clear],
                    center: .center, startRadius: 0, endRadius: diameter / 2)
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 55)
            .position(position)
    }
}
#endif
