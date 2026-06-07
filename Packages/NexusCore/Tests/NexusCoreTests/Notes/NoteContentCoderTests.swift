import Foundation
import Testing

@testable import NexusCore

@Suite("NoteContentCoder")
struct NoteContentCoderTests {
    @Test("empty data decodes as an empty document, not a throw")
    func emptyDataDecodesEmpty() throws {
        #expect(try NoteContentCoder.decode(Data()) == [])
    }

    @Test("encode then decode is identity")
    func roundTrip() throws {
        let blocks = [
            Block(kind: .heading(level: 1, runs: [InlineRun(text: "Title")])),
            Block(kind: .paragraph(runs: [InlineRun(text: "Body")])),
            Block(kind: .divider),
        ]
        let data = try NoteContentCoder.encode(blocks)
        #expect(try NoteContentCoder.decode(data) == blocks)
    }

    @Test("encoded bytes are stable across two encodes (sorted keys)")
    func deterministicBytes() throws {
        let blocks = [Block(kind: .paragraph(runs: [InlineRun(text: "x", marks: [.bold])]))]
        let first = try NoteContentCoder.encode(blocks)
        let second = try NoteContentCoder.encode(blocks)
        #expect(first == second)
    }
}
