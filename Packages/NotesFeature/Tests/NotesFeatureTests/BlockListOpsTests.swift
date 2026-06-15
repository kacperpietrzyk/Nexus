import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("BlockListOps")
struct BlockListOpsTests {

    @Test("insert after a known id places the block right after it")
    func insertAfter() {
        let a = Block(kind: .paragraph(runs: [InlineRun(text: "a")]))
        let b = Block(kind: .paragraph(runs: [InlineRun(text: "b")]))
        let new = BlockListOps.makeBlock(.divider)

        let result = BlockListOps.insert(new, after: a.id, in: [a, b])

        #expect(result.map(\.id) == [a.id, new.id, b.id])
    }

    @Test("insert with nil anchor appends")
    func insertAppend() {
        let a = Block(kind: .paragraph(runs: []))
        let new = BlockListOps.makeBlock(.paragraph)
        let result = BlockListOps.insert(new, after: nil, in: [a])
        #expect(result.last?.id == new.id)
    }

    @Test("remove drops the matching block and preserves the rest")
    func remove() {
        let a = Block(kind: .paragraph(runs: []))
        let b = Block(kind: .divider)
        let result = BlockListOps.remove(id: a.id, in: [a, b])
        #expect(result.map(\.id) == [b.id])
    }

    @Test("setRuns rewrites a paragraph's runs but keeps its id")
    func setRuns() {
        let a = Block(kind: .paragraph(runs: [InlineRun(text: "old")]))
        let result = BlockListOps.setRuns([InlineRun(text: "new")], forBlock: a.id, in: [a])
        #expect(result.first?.id == a.id)
        if case .paragraph(let runs) = result.first?.kind {
            #expect(runs == [InlineRun(text: "new")])
        } else {
            Issue.record("expected paragraph")
        }
    }

    @Test("setRuns is a no-op for a todo block (task title is the source of truth)")
    func setRunsTodoNoOp() {
        let ref = UUID()
        let todo = Block(kind: .todo(taskRef: ref, runs: [InlineRun(text: "keep")]))
        let result = BlockListOps.setRuns([InlineRun(text: "changed")], forBlock: todo.id, in: [todo])
        if case .todo(let taskRef, let runs) = result.first?.kind {
            #expect(taskRef == ref)
            #expect(runs == [InlineRun(text: "keep")])
        } else {
            Issue.record("expected unchanged todo")
        }
    }

    @Test("convert paragraph→heading preserves runs and id")
    func convertParagraphToHeading() {
        let a = Block(kind: .paragraph(runs: [InlineRun(text: "Title")]))
        let result = BlockListOps.convert(blockID: a.id, to: .heading(level: 2), in: [a])
        #expect(result.first?.id == a.id)
        if case .heading(let level, let runs) = result.first?.kind {
            #expect(level == 2)
            #expect(runs == [InlineRun(text: "Title")])
        } else {
            Issue.record("expected heading")
        }
    }

    @Test("convert to todo mints a fresh taskRef and keeps runs")
    func convertToTodo() {
        let a = Block(kind: .paragraph(runs: [InlineRun(text: "do it")]))
        let result = BlockListOps.convert(blockID: a.id, to: .todo, in: [a])
        if case .todo(_, let runs) = result.first?.kind {
            #expect(runs == [InlineRun(text: "do it")])
        } else {
            Issue.record("expected todo")
        }
    }

    @Test("makeBlock(.todo) generates a non-nil taskRef")
    func makeTodoHasRef() {
        if case .todo(let ref, let runs) = BlockListOps.makeBlock(.todo).kind {
            #expect(runs.isEmpty)
            #expect(ref != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        } else {
            Issue.record("expected todo")
        }
    }

    @Test("makeBlock(.heading) clamps the level to 1...6")
    func headingClamp() {
        if case .heading(let level, _) = BlockListOps.makeBlock(.heading(level: 99)).kind {
            #expect(level == 6)
        } else {
            Issue.record("expected heading")
        }
    }

    @Test("setCode rewrites a code block's text keeping language + id")
    func setCode() {
        let a = Block(kind: .code(language: "swift", text: "old"))
        let result = BlockListOps.setCode("new", forBlock: a.id, in: [a])
        #expect(result.first?.id == a.id)
        if case .code(let language, let text) = result.first?.kind {
            #expect(language == "swift")
            #expect(text == "new")
        } else {
            Issue.record("expected code")
        }
    }

    @Test("move reorders blocks")
    func move() {
        let a = Block(kind: .paragraph(runs: []))
        let b = Block(kind: .divider)
        let c = Block(kind: .quote(runs: []))
        let result = BlockListOps.move(in: [a, b, c], from: IndexSet(integer: 0), to: 3)
        #expect(result.map(\.id) == [b.id, c.id, a.id])
    }

    // MARK: - Table authoring (GAP #5)

    /// The cells of a table block, or nil if `block` isn't a table.
    private func cells(of block: Block?) -> [[[InlineRun]]]? {
        guard case .table(let rows)? = block?.kind else { return nil }
        return rows.map(\.cells)
    }

    @Test("makeBlock(.table) is a 2×2 grid with a non-empty header row")
    func makeTableDefaultShape() {
        guard case .table(let rows) = BlockListOps.makeBlock(.table).kind else {
            Issue.record("expected table")
            return
        }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.cells.count == 2 })  // rectangular
        // Header cells carry placeholder text so the markdown round-trip survives
        // (a header row of empty cells can't anchor the separator on re-parse).
        let headerText = rows[0].cells.map { InlineRunRendering.plainText($0) }
        #expect(headerText.allSatisfy { !$0.isEmpty })
    }

    @Test("setTableCell rewrites one cell, keeps id + rectangularity")
    func setTableCell() {
        let table = BlockListOps.makeBlock(.table)
        let result = BlockListOps.setTableCell(
            [InlineRun(text: "x")], row: 1, column: 0, forBlock: table.id, in: [table])
        #expect(result.first?.id == table.id)
        let grid = cells(of: result.first)
        #expect(grid?[1][0] == [InlineRun(text: "x")])
        #expect(grid?.allSatisfy { $0.count == 2 } == true)
    }

    @Test("setTableCell out of bounds is a no-op")
    func setTableCellOutOfBounds() {
        let table = BlockListOps.makeBlock(.table)
        let result = BlockListOps.setTableCell(
            [InlineRun(text: "x")], row: 9, column: 9, forBlock: table.id, in: [table])
        #expect(result == [table])
    }

    @Test("addTableRow appends a row matching the column count")
    func addTableRow() {
        let table = BlockListOps.makeBlock(.table)
        let result = BlockListOps.addTableRow(forBlock: table.id, in: [table])
        let grid = cells(of: result.first)
        #expect(grid?.count == 3)
        #expect(grid?.last?.count == 2)  // matches existing column count
    }

    @Test("removeTableRow drops the last row but never below one")
    func removeTableRow() {
        let table = BlockListOps.makeBlock(.table)  // 2 rows
        let once = BlockListOps.removeTableRow(forBlock: table.id, in: [table])
        #expect(cells(of: once.first)?.count == 1)
        // Already at one row — removing again is a floor no-op (keeps the header).
        let twice = BlockListOps.removeTableRow(forBlock: once.first!.id, in: once)
        #expect(cells(of: twice.first)?.count == 1)
    }

    @Test("addTableColumn appends a cell to every row")
    func addTableColumn() {
        let table = BlockListOps.makeBlock(.table)
        let result = BlockListOps.addTableColumn(forBlock: table.id, in: [table])
        let grid = cells(of: result.first)
        #expect(grid?.allSatisfy { $0.count == 3 } == true)  // rectangular at 3 cols
    }

    @Test("removeTableColumn drops the last column on every row, floor at one")
    func removeTableColumn() {
        let table = BlockListOps.makeBlock(.table)  // 2 cols
        let once = BlockListOps.removeTableColumn(forBlock: table.id, in: [table])
        #expect(cells(of: once.first)?.allSatisfy { $0.count == 1 } == true)
        let twice = BlockListOps.removeTableColumn(forBlock: once.first!.id, in: once)
        #expect(cells(of: twice.first)?.allSatisfy { $0.count == 1 } == true)
    }

    @Test("a default table round-trips through the markdown fixpoint")
    func tableMarkdownRoundTrip() {
        let table = BlockListOps.makeBlock(.table)
        let markdown = BlockMarkdownSerializer.markdown(for: [table])
        let parsed = MarkdownBlockParser.parse(markdown)
        guard case .table(let rows)? = parsed.first?.kind else {
            Issue.record("expected the serialized table to re-parse as a table; got \(markdown)")
            return
        }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.cells.count == 2 })
    }
}
