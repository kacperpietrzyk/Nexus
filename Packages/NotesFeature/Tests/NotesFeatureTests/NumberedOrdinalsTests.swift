import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("NumberedOrdinals")
@MainActor
struct NumberedOrdinalsTests {
    private func block(_ kind: BlockKind) -> Block { Block(kind: kind) }

    @Test("consecutive numbered blocks count 1..n; a non-numbered block resets the run")
    func ordinals() {
        let n1 = block(.numbered(runs: [InlineRun(text: "a")]))
        let n2 = block(.numbered(runs: [InlineRun(text: "b")]))
        let para = block(.paragraph(runs: [InlineRun(text: "break")]))
        let n3 = block(.numbered(runs: [InlineRun(text: "c")]))
        let n4 = block(.numbered(runs: [InlineRun(text: "d")]))

        let map = NumberedOrdinals.ordinals(for: [n1, n2, para, n3, n4])

        #expect(map[n1.id] == 1)
        #expect(map[n2.id] == 2)
        #expect(map[para.id] == nil)
        #expect(map[n3.id] == 1)
        #expect(map[n4.id] == 2)
    }
}
