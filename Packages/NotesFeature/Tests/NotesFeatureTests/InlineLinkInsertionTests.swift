import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("InlineLinkInsertion")
struct InlineLinkInsertionTests {

    private func candidate(_ title: String) -> LinkCandidate {
        LinkCandidate(id: UUID(), kind: .note, title: title)
    }

    // MARK: - detectTrigger

    @Test("detects a trailing [[ trigger and its query")
    func detectTrailing() {
        let trigger = InlineLinkInsertion.detectTrigger(in: "see [[Pro")
        #expect(trigger?.query == "Pro")
        #expect(trigger?.range == 4..<9)
    }

    @Test("detects a bare [[ with an empty query")
    func detectEmptyQuery() {
        let trigger = InlineLinkInsertion.detectTrigger(in: "open [[")
        #expect(trigger?.query.isEmpty == true)
        #expect(trigger?.range == 5..<7)
    }

    @Test("no trigger without an opener")
    func noOpener() {
        #expect(InlineLinkInsertion.detectTrigger(in: "plain text") == nil)
    }

    @Test("an already-closed wikilink is not an open trigger")
    func closedIsNotTrigger() {
        #expect(InlineLinkInsertion.detectTrigger(in: "see [[Done]] now") == nil)
    }

    @Test("uses the most recent opener when several appear")
    func mostRecentOpener() {
        // First wikilink is closed; the second is still open.
        let trigger = InlineLinkInsertion.detectTrigger(in: "[[A]] then [[B")
        #expect(trigger?.query == "B")
        #expect(trigger?.range.lowerBound == 11)
    }

    @Test("query spanning a newline is not a trigger")
    func newlineBreaksTrigger() {
        #expect(InlineLinkInsertion.detectTrigger(in: "[[multi\nline") == nil)
    }

    // MARK: - splice

    @Test("splice replaces the [[query token with a link run, keeping surrounding text")
    func spliceMidText() {
        let draft = "see [[Pro"
        let trigger = InlineLinkInsertion.detectTrigger(in: draft)!
        let target = candidate("Project X")
        let runs = InlineLinkInsertion.splice(draft: draft, trigger: trigger, candidate: target)

        #expect(runs.count == 2)
        #expect(runs[0] == InlineRun(text: "see "))
        #expect(runs[1].text == "Project X")
        #expect(runs[1].marks == [.link(ref: target.id, href: nil)])
    }

    @Test("splice with surrounding text on both sides yields prefix, link, suffix")
    func spliceWithSuffix() {
        // Build a trigger manually so a suffix survives (detectTrigger is trailing).
        let draft = "a [[q b"
        let trigger = InlineLinkInsertion.Trigger(query: "q b", range: 2..<7)
        let target = candidate("Linked")
        let runs = InlineLinkInsertion.splice(draft: draft, trigger: trigger, candidate: target)
        #expect(runs.map(\.text) == ["a ", "Linked"])
    }

    @Test("splice at the very start drops the empty prefix run")
    func spliceAtStart() {
        let draft = "[[X"
        let trigger = InlineLinkInsertion.detectTrigger(in: draft)!
        let runs = InlineLinkInsertion.splice(draft: draft, trigger: trigger, candidate: candidate("Target"))
        #expect(runs.count == 1)
        #expect(runs[0].text == "Target")
        #expect(runs[0].marks.contains { if case .link = $0 { return true } else { return false } })
    }

    // MARK: - wrapSelection

    @Test("wrapSelection turns a selected substring into a link titled by the candidate")
    func wrapMiddle() {
        let target = candidate("Real Title")
        let runs = InlineLinkInsertion.wrapSelection(text: "go here now", range: 3..<7, candidate: target)
        // "go " + link + " now"
        #expect(runs.map(\.text) == ["go ", "Real Title", " now"])
        #expect(runs[1].marks == [.link(ref: target.id, href: nil)])
    }

    @Test("wrapSelection clamps an out-of-range selection")
    func wrapClamps() {
        let runs = InlineLinkInsertion.wrapSelection(text: "abc", range: 1..<99, candidate: candidate("T"))
        #expect(runs.map(\.text) == ["a", "T"])
    }
}
