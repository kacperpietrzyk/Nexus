import CoreGraphics

/// Places up to `maxNodes` non-overlapping pill rects inside `size`.
///
/// Strategy:
///  1. Cap node count at `maxNodes`.
///  2. Attempt to place on a ring whose radius is computed so adjacent pills
///     can't overlap.  After computing positions we verify pairwise
///     non-overlap and bounds-containment; if either check fails we fall
///     back to…
///  3. A top-to-bottom stacked column centred horizontally, which trivially
///     satisfies non-overlap for any reasonable pill count + size.
///
/// Pure function — no SwiftUI, no state.
func placeNodes(
    _ count: Int,
    in size: CGSize,
    pillSize: CGSize,
    maxNodes: Int
) -> [CGRect] {
    let n = min(count, maxNodes)
    guard n > 0, size.width > 0, size.height > 0 else { return [] }

    let cx = size.width / 2
    let cy = size.height / 2

    // --- Attempt ring placement ---
    if n > 1 {
        // Minimum ring radius so no two adjacent pills overlap.
        // Arc distance between centres = 2π/n * r  ≥  longer pill diagonal + 2pt gap.
        let diagonal = (pillSize.width * pillSize.width + pillSize.height * pillSize.height).squareRoot()
        let minGap: CGFloat = 4
        let minRadius = (diagonal + minGap) / (2 * sin(.pi / CGFloat(n)))

        // Maximum radius so pills stay inside bounds.
        let maxRadiusX = cx - pillSize.width / 2 - 2
        let maxRadiusY = cy - pillSize.height / 2 - 2
        let maxRadius = min(maxRadiusX, maxRadiusY)

        if minRadius <= maxRadius {
            let r = minRadius
            var rects: [CGRect] = []
            var valid = true
            for i in 0..<n {
                let angle = (CGFloat(i) / CGFloat(n)) * 2 * .pi - .pi / 2
                let px = cx + r * cos(angle) - pillSize.width / 2
                let py = cy + r * sin(angle) - pillSize.height / 2
                let rect = CGRect(origin: CGPoint(x: px, y: py), size: pillSize)
                rects.append(rect)
            }

            // Verify: pairwise non-overlap + within bounds.
            // Use `intersects` for pairwise check (touching edges are acceptable;
            // a positive-area intersection means actual visual overlap).
            let bounds = CGRect(origin: .zero, size: size)
            for i in rects.indices {
                guard bounds.contains(rects[i]) else { valid = false; break }
                for j in rects.indices where j > i {
                    // Shrink slightly before intersects check to allow edge-touching
                    // (two pills whose edges meet at a pixel boundary don't overlap visually).
                    let a = rects[i].insetBy(dx: 0.5, dy: 0.5)
                    let b = rects[j].insetBy(dx: 0.5, dy: 0.5)
                    if a.intersects(b) {
                        valid = false; break
                    }
                }
                if !valid { break }
            }

            if valid { return rects }
        }
    }

    // --- Fallback: stacked column centred horizontally ---
    let gap: CGFloat = 6
    let totalH = CGFloat(n) * pillSize.height + CGFloat(max(0, n - 1)) * gap
    let startY = (size.height - totalH) / 2
    let startX = (size.width - pillSize.width) / 2

    return (0..<n).map { i in
        CGRect(
            x: startX,
            y: startY + CGFloat(i) * (pillSize.height + gap),
            width: pillSize.width,
            height: pillSize.height
        )
    }
}
