import CoreGraphics
import Foundation
import NexusCore

/// Maps engine world space to view space: scale around the view center, then
/// translate by the pan offset. Pure math, unit-tested apart from gestures.
public struct GraphViewTransform: Equatable, Sendable {
    public static let zoomRange: ClosedRange<CGFloat> = 0.25...4

    public private(set) var zoom: CGFloat = 1
    public var pan: CGSize = .zero

    public init() {}

    public mutating func setZoom(_ value: CGFloat) {
        zoom = min(max(value, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
    }

    public func screenPoint(for world: SIMD2<Double>, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + pan.width + CGFloat(world.x) * zoom,
            y: size.height / 2 + pan.height + CGFloat(world.y) * zoom
        )
    }

    public func worldPoint(for screen: CGPoint, in size: CGSize) -> SIMD2<Double> {
        SIMD2(
            Double((screen.x - size.width / 2 - pan.width) / zoom),
            Double((screen.y - size.height / 2 - pan.height) / zoom)
        )
    }

    /// Nearest node whose screen-space distance is within `hitRadius` points.
    public func hitTest(
        _ screen: CGPoint,
        nodeIDs: [GraphNodeID],
        positions: [SIMD2<Double>],
        in size: CGSize,
        hitRadius: CGFloat = 14
    ) -> GraphNodeID? {
        var best: (nodeID: GraphNodeID, distance: CGFloat)?
        for (index, world) in positions.enumerated() where index < nodeIDs.count {
            let point = screenPoint(for: world, in: size)
            let dx = point.x - screen.x
            let dy = point.y - screen.y
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= hitRadius, distance < (best?.distance ?? .infinity) {
                best = (nodeIDs[index], distance)
            }
        }
        return best?.nodeID
    }
}
