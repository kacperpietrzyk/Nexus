import CoreGraphics
import Testing

@testable import NexusMeetings

@Suite("BacklinksGraphLayout")
struct BacklinksGraphLayoutTests {

    @Test
    func miniGraphNodesDoNotOverlap() {
        let rects = placeNodes(
            8,
            in: CGSize(width: 256, height: 180),
            pillSize: CGSize(width: 88, height: 22),
            maxNodes: 5
        )
        #expect(rects.count <= 5)
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(!rects[i].intersects(rects[j]))
            }
            #expect(
                CGRect(
                    origin: .zero,
                    size: CGSize(width: 256, height: 180)
                ).contains(rects[i])
            )
        }
    }
}
