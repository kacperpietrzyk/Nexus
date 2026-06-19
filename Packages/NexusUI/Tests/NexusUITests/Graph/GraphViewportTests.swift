import CoreGraphics
import Testing
@testable import NexusUI

@Suite struct GraphViewportTests {
    @Test func projectCentersWorldOriginAtViewCenterAtUnitScale() {
        let vp = GraphViewport(scale: 1, offset: .zero)
        let p = vp.project(.zero, in: CGSize(width: 200, height: 100))
        #expect(p == CGPoint(x: 100, y: 50))
    }

    @Test func zoomMultipliesScaleClamped() {
        var vp = GraphViewport()
        vp.zoom(by: 2)
        #expect(vp.scale == 2)
        vp.zoom(by: 0.001)
        #expect(vp.scale >= 0.2)  // clamped floor
        for _ in 0..<20 { vp.zoom(by: 4) }
        #expect(vp.scale <= 5)  // clamped ceil
    }

    @Test func fitCentersBoundsAndScalesToFit() {
        var vp = GraphViewport()
        vp.fit(
            worldBounds: CGRect(x: -50, y: -50, width: 100, height: 100),
            in: CGSize(width: 200, height: 200), padding: 20)
        let topLeft = vp.project(CGPoint(x: -50, y: -50), in: CGSize(width: 200, height: 200))
        #expect(topLeft.x >= 20 - 0.001 && topLeft.y >= 20 - 0.001)
    }
}
