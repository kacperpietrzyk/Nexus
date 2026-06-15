import Foundation
import Testing

@testable import NexusCore

/// Table cells must survive the serialize -> parse round-trip even when a cell's
/// text contains a metacharacter the line-based parser is sensitive to:
/// - a NEWLINE would break a `| … |` row across lines (the parser is line-based);
/// - an unescaped `|` would mis-split the columns.
/// The serializer collapses newlines to spaces and escapes `|` -> `\|` in cells;
/// the parser splits cells escape-aware and unescapes `\|` back to `|`.
@Suite("Table cell round-trip (newline + pipe)")
struct TableCellRoundTripTests {
    private func roundTrip(_ rows: [TableRow]) -> Block? {
        let markdown = BlockMarkdownSerializer.markdown(for: [Block(kind: .table(rows: rows))])
        return MarkdownBlockParser.parse(markdown).first
    }

    private func cellTexts(_ block: Block?) -> [[String]]? {
        guard case .table(let rows)? = block?.kind else { return nil }
        return rows.map { row in row.cells.map { $0.map(\.text).joined() } }
    }

    @Test("a cell containing a newline stays one row")
    func newlineInCellRoundTrips() {
        let rows = [
            TableRow(cells: [[InlineRun(text: "Header A")], [InlineRun(text: "Header B")]]),
            TableRow(cells: [[InlineRun(text: "line1\nline2")], [InlineRun(text: "ok")]]),
        ]
        let parsed = cellTexts(roundTrip(rows))
        // Two rows preserved (header + body); the newline became a space, not a row break.
        #expect(parsed == [["Header A", "Header B"], ["line1 line2", "ok"]])
    }

    @Test("a cell containing a pipe does not mis-split columns")
    func pipeInCellRoundTrips() {
        let rows = [
            TableRow(cells: [[InlineRun(text: "Key")], [InlineRun(text: "Value")]]),
            TableRow(cells: [[InlineRun(text: "a|b")], [InlineRun(text: "c")]]),
        ]
        let parsed = cellTexts(roundTrip(rows))
        // The literal pipe stays inside the single cell — still two columns per row.
        #expect(parsed == [["Key", "Value"], ["a|b", "c"]])
    }
}
