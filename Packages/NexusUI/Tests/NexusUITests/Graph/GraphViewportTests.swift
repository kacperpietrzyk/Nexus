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

    @Test func fitFocusedPinsFocusAtViewportCenter() {
        var vp = GraphViewport()
        let size = CGSize(width: 400, height: 300)
        let focus = CGPoint(x: 30, y: -10)  // off-origin: must still land dead-center
        let points = [focus, CGPoint(x: 130, y: -10), CGPoint(x: 30, y: 90), CGPoint(x: -70, y: -110)]
        vp.fitFocused(on: focus, points: points, in: size, padding: 24)
        let projected = vp.project(focus, in: size)
        #expect(abs(projected.x - size.width / 2) < 0.001)
        #expect(abs(projected.y - size.height / 2) < 0.001)
    }

    @Test func fitFocusedKeepsEveryNodeInsideViewport() {
        var vp = GraphViewport()
        let size = CGSize(width: 400, height: 300)
        let focus = CGPoint.zero
        let points = [focus, CGPoint(x: 500, y: 0), CGPoint(x: 0, y: -400), CGPoint(x: -260, y: 220)]
        vp.fitFocused(on: focus, points: points, in: size, padding: 20)
        for point in points {
            let p = vp.project(point, in: size)
            #expect(p.x >= 20 - 0.5 && p.x <= size.width - 20 + 0.5)
            #expect(p.y >= 20 - 0.5 && p.y <= size.height - 20 + 0.5)
        }
    }
}
