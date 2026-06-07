import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("InlineRunRendering")
struct InlineRunRenderingTests {

    @Test("plainText joins run texts in order")
    func plainText() {
        let runs = [InlineRun(text: "Hello "), InlineRun(text: "world", marks: [.bold])]
        #expect(InlineRunRendering.plainText(runs) == "Hello world")
    }

    @Test("runs(fromPlainText:) round-trips a plain line losslessly")
    func plainTextRoundTrip() {
        let text = "a plain line of prose"
        let runs = InlineRunRendering.runs(fromPlainText: text)
        #expect(InlineRunRendering.plainText(runs) == text)
    }

    @Test("empty text yields no runs")
    func emptyText() {
        #expect(InlineRunRendering.runs(fromPlainText: "").isEmpty)
    }

    @Test("attributed renders all run text concatenated")
    func attributedText() {
        let runs = [InlineRun(text: "foo"), InlineRun(text: "bar", marks: [.italic])]
        let attributed = InlineRunRendering.attributed(runs)
        #expect(String(attributed.characters) == "foobar")
    }

    @Test("a wikilink ref encodes a nexus://note-ref URL that round-trips")
    func wikilinkRoundTrip() {
        let ref = UUID()
        let runs = [InlineRun(text: "Project", marks: [.link(ref: ref, href: nil)])]
        let attributed = InlineRunRendering.attributed(runs)
        let link = attributed.runs.compactMap(\.link).first
        let url = try? #require(link)
        if let url {
            #expect(InlineRunRendering.wikilinkTarget(from: url) == ref)
        }
    }

    @Test("a plain href is preserved as a normal URL, not a wikilink")
    func externalLink() {
        let runs = [InlineRun(text: "site", marks: [.link(ref: nil, href: "https://example.com")])]
        let attributed = InlineRunRendering.attributed(runs)
        let url = attributed.runs.compactMap(\.link).first
        #expect(url == URL(string: "https://example.com"))
        if let url {
            #expect(InlineRunRendering.wikilinkTarget(from: url) == nil)
        }
    }

    @Test("wikilinkTarget rejects a non-nexus URL")
    func rejectsExternalScheme() {
        let url = URL(string: "https://example.com")!
        #expect(InlineRunRendering.wikilinkTarget(from: url) == nil)
    }
}
