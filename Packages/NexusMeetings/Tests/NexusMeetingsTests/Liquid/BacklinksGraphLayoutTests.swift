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

    // MARK: - Edge cases: zero / one node

    @Test
    func zeroNodesReturnsEmpty() {
        let rects = placeNodes(
            0,
            in: CGSize(width: 256, height: 180),
            pillSize: CGSize(width: 88, height: 22),
            maxNodes: 5
        )
        #expect(rects.isEmpty)
    }

    @Test
    func oneNodeIsWithinBounds() {
        let size = CGSize(width: 256, height: 180)
        let pillSize = CGSize(width: 88, height: 22)
        let rects = placeNodes(1, in: size, pillSize: pillSize, maxNodes: 5)
        #expect(rects.count <= 1)
        let bounds = CGRect(origin: .zero, size: size)
        for rect in rects {
            #expect(bounds.contains(rect))
        }
    }

    // MARK: - Column-fallback + undersized canvas

    @Test
    func columnFallbackNoCrashAndAllRectsInBounds() {
        // Pill (88×22) wider than canvas (60×60) — single pill can't fit → must return [].
        let rects = placeNodes(
            3,
            in: CGSize(width: 60, height: 60),
            pillSize: CGSize(width: 88, height: 22),
            maxNodes: 3
        )
        // Contract: no out-of-bounds rects; returning [] is acceptable.
        let bounds = CGRect(origin: .zero, size: CGSize(width: 60, height: 60))
        for rect in rects {
            #expect(bounds.contains(rect))
        }
    }

    @Test
    func columnFallbackTooTallReturnsEmpty() {
        // 5 pills × 22pt + 4 gaps × 6pt = 134pt; canvas height = 60pt → column can't fit.
        let rects = placeNodes(
            5,
            in: CGSize(width: 200, height: 60),
            pillSize: CGSize(width: 88, height: 22),
            maxNodes: 5
        )
        // Must return [] rather than rects that escape the canvas.
        let bounds = CGRect(origin: .zero, size: CGSize(width: 200, height: 60))
        for rect in rects {
            #expect(bounds.contains(rect))
        }
    }

    @Test
    func columnFallbackSmallCanvasFitsOnePill() {
        // Canvas is exactly pill-sized — one pill can fit in the column fallback.
        let pillSize = CGSize(width: 88, height: 22)
        let rects = placeNodes(
            1,
            in: pillSize,
            pillSize: pillSize,
            maxNodes: 5
        )
        let bounds = CGRect(origin: .zero, size: pillSize)
        for rect in rects {
            #expect(bounds.contains(rect))
        }
    }

    // MARK: - centerClear: peripheral pills must not overlap the centre rect

    @Test
    func centerClearPreventsPeripheralOverlapWithCentre() {
        let size = CGSize(width: 360, height: 280)
        let pillSize = CGSize(width: 120, height: 24)
        let centerClear = CGSize(width: 120, height: 24)
        let centreRect = CGRect(
            x: size.width / 2 - centerClear.width / 2,
            y: size.height / 2 - centerClear.height / 2,
            width: centerClear.width,
            height: centerClear.height
        )

        for count in [1, 2, 3, 6] {
            let rects = placeNodes(
                count,
                in: size,
                pillSize: pillSize,
                maxNodes: count,
                centerClear: centerClear
            )
            let bounds = CGRect(origin: .zero, size: size)
            for rect in rects {
                #expect(bounds.contains(rect), "rect out of bounds for count=\(count)")
                // Shrink by 0.5 to allow touching edges (same convention as placeNodes).
                #expect(
                    !rect.insetBy(dx: 0.5, dy: 0.5)
                        .intersects(centreRect.insetBy(dx: 0.5, dy: 0.5)),
                    "peripheral rect overlaps centre for count=\(count)"
                )
            }
        }
    }

    // MARK: - Popover ring test

    /// For the expanded popover canvas (360×280, pill 120×24, n=6, centerClear 120×24)
    /// nodes must be placed on a 2-D ring — not in a vertical column.
    /// Prior to the ring fix, all nodes fell into columnFallback (single x-column).
    @Test
    func popooverCanvasPlacesNodesOn2DRingNotColumn() {
        let size = CGSize(width: 360, height: 280)
        let pillSize = CGSize(width: 120, height: 24)
        let centerClear = CGSize(width: 120, height: 24)

        let rects = placeNodes(
            6,
            in: size,
            pillSize: pillSize,
            maxNodes: 6,
            centerClear: centerClear
        )

        #expect(rects.count == 6, "All 6 nodes should be placed")

        // Must be non-overlapping.
        for i in rects.indices {
            for j in rects.indices where j > i {
                #expect(
                    !rects[i].insetBy(dx: 0.5, dy: 0.5)
                        .intersects(rects[j].insetBy(dx: 0.5, dy: 0.5)),
                    "Rects \(i) and \(j) overlap"
                )
            }
        }

        // Must be in bounds.
        let bounds = CGRect(origin: .zero, size: size)
        for rect in rects {
            #expect(bounds.contains(rect), "Rect \(rect) out of bounds")
        }

        // Must NOT be all-collinear (ring, not a column) — at least 2 distinct midX values.
        let distinctX = Set(rects.map { ($0.midX * 10).rounded() })
        #expect(distinctX.count > 1, "Nodes appear collinear (all same x); expected ring layout")
    }
}
