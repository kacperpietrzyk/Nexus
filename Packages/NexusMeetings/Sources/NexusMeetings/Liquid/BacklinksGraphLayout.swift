import CoreGraphics

/// Places up to `maxNodes` non-overlapping pill rects inside `size`.
///
/// Strategy:
///  1. Cap node count at `maxNodes`.
///  2. Attempt to place on a ring whose radius is computed so adjacent pills
///     can't overlap AND clears the optional `centerClear` reserved rect at the
///     canvas centre.  After computing positions we verify pairwise
///     non-overlap and bounds-containment; if either check fails we fall
///     back to…
///  3. A top-to-bottom stacked column centred horizontally.  When a centre
///     reserved rect is present the column is split into a top half and a
///     bottom half so no pill overlaps the centre element.
///
/// - Parameters:
///   - count:       Number of nodes to place (capped at `maxNodes`).
///   - size:        Canvas bounds; all returned rects are guaranteed to lie
///                  within `CGRect(origin: .zero, size: size)`.
///   - pillSize:    Fixed width × height of every peripheral pill.
///   - maxNodes:    Hard cap on returned rects.
///   - centerClear: Optional size of a reserved rect centred on the canvas
///                  (e.g. a centre pill).  The ring radius is expanded so no
///                  peripheral pill overlaps this area.  Pass `.zero` (default)
///                  when there is no central element to avoid.
///
/// Returns `[]` when no valid placement exists (canvas too small, ring radius
/// exceeds bounds, or split column can't fit).
///
/// Pure function — no SwiftUI, no state.
func placeNodes(
    _ count: Int,
    in size: CGSize,
    pillSize: CGSize,
    maxNodes: Int,
    centerClear: CGSize = .zero
) -> [CGRect] {
    BacklinksLayout(
        count: count, size: size, pillSize: pillSize,
        maxNodes: maxNodes, centerClear: centerClear
    ).place()
}

// MARK: - Layout engine

/// Encapsulates all layout state so helpers share context without long param lists.
private struct BacklinksLayout {

    let n: Int
    let size: CGSize
    let pillSize: CGSize
    let minGap: CGFloat = 4
    let centreRect: CGRect

    init(count: Int, size: CGSize, pillSize: CGSize, maxNodes: Int, centerClear: CGSize) {
        self.n = min(count, maxNodes)
        self.size = size
        self.pillSize = pillSize
        let cx = size.width / 2
        let cy = size.height / 2
        self.centreRect =
            centerClear == .zero
            ? .null
            : CGRect(
                x: cx - centerClear.width / 2,
                y: cy - centerClear.height / 2,
                width: centerClear.width,
                height: centerClear.height
            )
    }

    var cx: CGFloat { size.width / 2 }
    var cy: CGFloat { size.height / 2 }

    /// Max ring radius so pills stay inside canvas bounds.
    var maxRadius: CGFloat {
        min(cx - pillSize.width / 2 - 2, cy - pillSize.height / 2 - 2)
    }

    var pillDiag: CGFloat {
        (pillSize.width * pillSize.width + pillSize.height * pillSize.height).squareRoot()
    }

    var clearDiag: CGFloat {
        guard !centreRect.isNull else { return 0 }
        let w = centreRect.width
        let h = centreRect.height
        return (w * w + h * h).squareRoot()
    }

    /// Minimum ring radius so peripheral pills clear the centre reserved rect
    /// (conservative diagonal bound; 0 when there is no centre element).
    var minRadiusFromCenter: CGFloat {
        clearDiag > 0 ? pillDiag / 2 + clearDiag / 2 + minGap : 0
    }

    // MARK: Entry point

    func place() -> [CGRect] {
        guard n > 0, size.width > 0, size.height > 0 else { return [] }
        guard pillSize.width <= size.width, pillSize.height <= size.height else { return [] }

        if n == 1 && minRadiusFromCenter > 0 { return singleNodeOffset() }
        if n > 1, let rects = ringAttempt() { return rects }
        return columnFallback()
    }

    // MARK: Helpers

    /// Returns true when `rect` is within canvas bounds and does not intersect
    /// the centre reserved rect (when one is set).
    func isPlaceable(_ rect: CGRect) -> Bool {
        guard CGRect(origin: .zero, size: size).contains(rect) else { return false }
        if !centreRect.isNull {
            if rect.insetBy(dx: 0.5, dy: 0.5).intersects(centreRect.insetBy(dx: 0.5, dy: 0.5)) {
                return false
            }
        }
        return true
    }

    /// Places a single node above (or near) centre to avoid the reserved rect.
    func singleNodeOffset() -> [CGRect] {
        guard minRadiusFromCenter <= maxRadius else { return [] }
        for step in 0..<8 {
            let angle = -.pi / 2 + CGFloat(step) * (.pi / 4)
            let px = cx + minRadiusFromCenter * cos(angle) - pillSize.width / 2
            let py = cy + minRadiusFromCenter * sin(angle) - pillSize.height / 2
            let rect = CGRect(origin: CGPoint(x: px, y: py), size: pillSize)
            if isPlaceable(rect) { return [rect] }
        }
        return []
    }

    /// Attempts ring placement.  Tries the spacing-only radius first (may already
    /// clear centre post-hoc), then the centre-expanded radius, then the maximum
    /// in-bounds radius (maximises angular separation for wide-short pills where
    /// the diagonal-based bound is over-conservative).
    func ringAttempt() -> [CGRect]? {
        let minFromSpacing = (pillDiag + minGap) / (2 * sin(.pi / CGFloat(n)))
        let candidates = [minFromSpacing, max(minFromSpacing, minRadiusFromCenter), maxRadius]
        for r in candidates {
            guard r <= maxRadius else { continue }
            if let rects = ringRects(radius: r) { return rects }
        }
        return nil
    }

    func ringRects(radius: CGFloat) -> [CGRect]? {
        var rects: [CGRect] = []
        for i in 0..<n {
            let angle = (CGFloat(i) / CGFloat(n)) * 2 * .pi - .pi / 2
            let px = cx + radius * cos(angle) - pillSize.width / 2
            let py = cy + radius * sin(angle) - pillSize.height / 2
            rects.append(CGRect(origin: CGPoint(x: px, y: py), size: pillSize))
        }
        for i in rects.indices {
            guard isPlaceable(rects[i]) else { return nil }
            for j in rects.indices where j > i {
                let a = rects[i].insetBy(dx: 0.5, dy: 0.5)
                let b = rects[j].insetBy(dx: 0.5, dy: 0.5)
                if a.intersects(b) { return nil }
            }
        }
        return rects
    }

    /// Stacked column.  When a centre reserved rect is present, the column is
    /// split above and below the centre so no pill overlaps it.
    func columnFallback() -> [CGRect] {
        let gap = minGap + 2  // slightly wider gap in column mode
        let startX = cx - pillSize.width / 2

        if !centreRect.isNull {
            return splitColumn(gap: gap, startX: startX)
        }

        let totalH = CGFloat(n) * pillSize.height + CGFloat(max(0, n - 1)) * gap
        guard totalH <= size.height else { return [] }
        let startY = (size.height - totalH) / 2
        return (0..<n).map { i in
            CGRect(
                x: startX, y: startY + CGFloat(i) * (pillSize.height + gap),
                width: pillSize.width, height: pillSize.height
            )
        }
    }

    func splitColumn(gap: CGFloat, startX: CGFloat) -> [CGRect] {
        let topCount = (n + 1) / 2
        let bottomCount = n / 2
        let topH = CGFloat(topCount) * pillSize.height + CGFloat(max(0, topCount - 1)) * gap
        let topStartY = centreRect.minY - gap - topH
        let bottomMin = centreRect.maxY + gap
        let bottomH = CGFloat(bottomCount) * pillSize.height + CGFloat(max(0, bottomCount - 1)) * gap
        guard topStartY >= 0, bottomMin + bottomH <= size.height else { return [] }

        var rects: [CGRect] = []
        for i in 0..<topCount {
            let y = topStartY + CGFloat(i) * (pillSize.height + gap)
            rects.append(CGRect(x: startX, y: y, width: pillSize.width, height: pillSize.height))
        }
        for i in 0..<bottomCount {
            let y = bottomMin + CGFloat(i) * (pillSize.height + gap)
            rects.append(CGRect(x: startX, y: y, width: pillSize.width, height: pillSize.height))
        }
        guard rects.allSatisfy({ isPlaceable($0) }) else { return [] }
        return rects
    }
}
