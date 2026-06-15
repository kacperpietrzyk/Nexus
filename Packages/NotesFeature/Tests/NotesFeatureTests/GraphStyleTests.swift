import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("GraphStyle - node styling rules")
struct GraphStyleTests {
    @Test("every renderable kind has a glyph and an ordered filter slot")
    func renderableKindsCovered() {
        #expect(Set(GraphStyle.filterableKinds) == GraphAssembler.renderableKinds)
        for kind in GraphStyle.filterableKinds {
            #expect(!GraphStyle.glyph(for: kind).isEmpty)
        }
    }

    @Test("node radius grows with degree and stays bounded")
    func radiusBounded() {
        let base = GraphStyle.nodeRadius(degree: 0)
        let mid = GraphStyle.nodeRadius(degree: 9)
        let huge = GraphStyle.nodeRadius(degree: 10_000)
        #expect(base < mid)
        #expect(mid <= huge)
        #expect(huge <= 14)
    }

    @Test("display title falls back for empty and truncates long titles")
    func displayTitle() {
        #expect(GraphStyle.displayTitle("") == "Untitled")
        #expect(GraphStyle.displayTitle("short") == "short")
        let long = String(repeating: "x", count: 60)
        let shown = GraphStyle.displayTitle(long)
        #expect(shown.count <= 29)
        #expect(shown.hasSuffix("…"))
    }
}
