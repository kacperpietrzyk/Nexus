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
}
