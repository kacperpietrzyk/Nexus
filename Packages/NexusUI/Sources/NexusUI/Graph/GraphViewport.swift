import CoreGraphics

/// Pan/zoom transform from world (force-layout) space to view space.
/// World origin maps to view center, then scaled and offset.
public struct GraphViewport: Equatable {
    public var scale: CGFloat
    public var offset: CGSize
    public static let minScale: CGFloat = 0.2
    public static let maxScale: CGFloat = 5

    public init(scale: CGFloat = 1, offset: CGSize = .zero) {
        self.scale = scale
        self.offset = offset
    }

    public func project(_ world: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width / 2 + offset.width + world.x * scale,
            y: size.height / 2 + offset.height + world.y * scale)
    }

    public mutating func zoom(by factor: CGFloat) {
        scale = min(Self.maxScale, max(Self.minScale, scale * factor))
    }

    public mutating func fit(worldBounds: CGRect, in size: CGSize, padding: CGFloat) {
        guard worldBounds.width > 0, worldBounds.height > 0 else { return }
        let sx = (size.width - 2 * padding) / worldBounds.width
        let sy = (size.height - 2 * padding) / worldBounds.height
        scale = min(Self.maxScale, max(Self.minScale, min(sx, sy)))
        let center = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        offset = CGSize(width: -center.x * scale, height: -center.y * scale)
    }
}
