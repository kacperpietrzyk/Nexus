import CoreGraphics
import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("GraphViewTransform - pan/zoom + hit testing")
struct GraphViewTransformTests {
    private let size = CGSize(width: 800, height: 600)

    @Test("identity maps world origin to the view center")
    func identityCentersOrigin() {
        let transform = GraphViewTransform()
        let point = transform.screenPoint(for: SIMD2(0, 0), in: size)
        #expect(point == CGPoint(x: 400, y: 300))
    }

    @Test("screen -> world -> screen round-trips under pan + zoom")
    func roundTrip() {
        var transform = GraphViewTransform()
        transform.setZoom(2)
        transform.pan = CGSize(width: 31, height: -17)

        let world = SIMD2<Double>(123.5, -42.25)
        let screen = transform.screenPoint(for: world, in: size)
        let back = transform.worldPoint(for: screen, in: size)
        #expect(abs(back.x - world.x) < 1e-9)
        #expect(abs(back.y - world.y) < 1e-9)
    }

    @Test("zoom clamps to the allowed range")
    func zoomClamps() {
        var transform = GraphViewTransform()
        transform.setZoom(100)
        #expect(transform.zoom == GraphViewTransform.zoomRange.upperBound)
        transform.setZoom(0.001)
        #expect(transform.zoom == GraphViewTransform.zoomRange.lowerBound)
    }

    @Test("hitTest returns the nearest node within the radius, nil outside")
    func hitTesting() {
        let transform = GraphViewTransform()
        let near = GraphNodeID(.note, UUID())
        let far = GraphNodeID(.task, UUID())
        let nodeIDs = [near, far]
        let positions: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(10, 0)]

        let hit = transform.hitTest(
            CGPoint(x: 404, y: 300), nodeIDs: nodeIDs, positions: positions, in: size
        )
        #expect(hit == near)

        let miss = transform.hitTest(
            CGPoint(x: 700, y: 100), nodeIDs: nodeIDs, positions: positions, in: size
        )
        #expect(miss == nil)
    }
}
