import Foundation
import Testing
@testable import TasksFeature

@Suite struct ProjectGlyphTests {
    // Stable UUIDs chosen so their derived shapes differ.
    private let a = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let b = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    @Test func explicitNonDefaultTokenWins() {
        #expect(nexusProjectGlyph(token: "gold", id: a) == "square.fill")
        #expect(nexusProjectGlyph(token: "rose", id: a) == "diamond.fill")
    }

    @Test func defaultTokenDerivesFromID() {
        // "azure" is the unset default → shape comes from the id, not the token.
        let shapeA = nexusProjectGlyph(token: "azure", id: a)
        let shapeB = nexusProjectGlyph(token: "azure", id: b)
        let known: Set = ["circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill"]
        #expect(known.contains(shapeA))
        #expect(known.contains(shapeB))
        #expect(shapeA != shapeB)  // these two ids must diverge
    }

    @Test func derivationIsStable() {
        #expect(nexusProjectGlyph(token: "azure", id: a) == nexusProjectGlyph(token: "azure", id: a))
    }

    @Test func unknownTokenDerivesToo() {
        let shape = nexusProjectGlyph(token: "not-a-token", id: a)
        #expect(shape == nexusProjectGlyph(token: "azure", id: a))
    }
}
