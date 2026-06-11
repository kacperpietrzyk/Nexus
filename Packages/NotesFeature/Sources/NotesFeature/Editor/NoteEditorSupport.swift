import Foundation
import NexusUI
import SwiftUI

/// Minimal flow layout: lays subviews left-to-right, wrapping to the next line
/// when the proposed width is exceeded. macOS/iOS 16+ `Layout`.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > maxWidth, cursorX > 0 {
                totalHeight += rowHeight + spacing
                cursorX = 0
                rowHeight = 0
            }
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? cursorX : maxWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var cursorX = bounds.minX
        var cursorY = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursorX + size.width > bounds.maxX, cursorX > bounds.minX {
                cursorX = bounds.minX
                cursorY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: cursorX, y: cursorY), proposal: ProposedViewSize(size))
            cursorX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct PickerContext: Identifiable {
    let id = UUID()
    let afterID: UUID?
    let asEmbed: Bool
}

struct BacklinkEntry: Identifiable {
    let id: UUID
    let title: String
}

/// A wrapping row of removable tag chips. Uses a small flow `Layout` so chips wrap
/// onto multiple lines instead of clipping or forcing a horizontal scroll inside
/// the editor's property panel.
struct FlowChips: View {
    let tags: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                NexusChip(tag, systemImage: "number", onRemove: { onRemove(tag) })
            }
        }
    }
}
