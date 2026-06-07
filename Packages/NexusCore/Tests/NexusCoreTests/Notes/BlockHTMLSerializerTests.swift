import Foundation
import Testing

@testable import NexusCore

@Suite("BlockHTMLSerializer")
struct BlockHTMLSerializerTests {
    @Test("paragraph wraps in <p> and escapes text")
    func paragraphEscapes() {
        let block = Block(kind: .paragraph(runs: [InlineRun(text: "a < b & c > d")]))
        #expect(BlockHTMLSerializer.html(for: [block]) == "<p>a &lt; b &amp; c &gt; d</p>")
    }

    @Test("heading clamps level into 1...6")
    func headingClamps() {
        let low = Block(kind: .heading(level: 0, runs: [InlineRun(text: "x")]))
        let high = Block(kind: .heading(level: 9, runs: [InlineRun(text: "x")]))
        #expect(BlockHTMLSerializer.html(for: [low]) == "<h1>x</h1>")
        #expect(BlockHTMLSerializer.html(for: [high]) == "<h6>x</h6>")
    }

    @Test("marks nest deterministically regardless of stored order")
    func markNesting() {
        let runsA = [InlineRun(text: "x", marks: [.bold, .italic])]
        let runsB = [InlineRun(text: "x", marks: [.italic, .bold])]
        let a = BlockHTMLSerializer.html(for: [Block(kind: .paragraph(runs: runsA))])
        let b = BlockHTMLSerializer.html(for: [Block(kind: .paragraph(runs: runsB))])
        #expect(a == b)
        #expect(a == "<p><strong><em>x</em></strong></p>")
    }

    @Test("inline code is escaped")
    func inlineCodeEscaped() {
        let run = InlineRun(text: "<script>", marks: [.code])
        let html = BlockHTMLSerializer.html(for: [Block(kind: .paragraph(runs: [run]))])
        #expect(html == "<p><code>&lt;script&gt;</code></p>")
    }

    @Test("code block content is escaped, language becomes a class")
    func codeBlockEscaped() {
        let block = Block(kind: .code(language: "swift", text: "let x = a < b"))
        let html = BlockHTMLSerializer.html(for: [block])
        #expect(html == "<pre><code class=\"language-swift\">let x = a &lt; b</code></pre>")
    }

    @Test("link with href escapes, wikilink with ref emits data-ref")
    func links() {
        let href = InlineRun(text: "t", marks: [.link(ref: nil, href: "https://x.test/?a=1&b=2")])
        let ref = UUID()
        let wiki = InlineRun(text: "t", marks: [.link(ref: ref, href: nil)])
        #expect(
            BlockHTMLSerializer.html(for: [Block(kind: .paragraph(runs: [href]))])
                == "<p><a href=\"https://x.test/?a=1&amp;b=2\">t</a></p>"
        )
        #expect(
            BlockHTMLSerializer.html(for: [Block(kind: .paragraph(runs: [wiki]))])
                == "<p><a data-ref=\"\(ref.uuidString)\">t</a></p>"
        )
    }

    @Test("html(raw) block is passed through unescaped (escape hatch)")
    func rawHTMLPassthrough() {
        let raw = "<div class=\"x\"><b>hi</b></div>"
        #expect(BlockHTMLSerializer.html(for: [Block(kind: .html(raw: raw))]) == raw)
    }

    @Test("divider, todo, lists, quote, image, embed, table render")
    func structuralBlocks() {
        let ref = UUID()
        #expect(BlockHTMLSerializer.html(for: [Block(kind: .divider)]) == "<hr>")
        #expect(
            BlockHTMLSerializer.html(for: [Block(kind: .todo(taskRef: ref, runs: [InlineRun(text: "do")]))])
                == "<li><input type=\"checkbox\" disabled> do</li>"
        )
        #expect(
            BlockHTMLSerializer.html(for: [Block(kind: .image(ref: nil, asset: "a&b.png"))])
                == "<img src=\"a&amp;b.png\">"
        )
        let embed = BlockHTMLSerializer.html(for: [Block(kind: .embed(ref: ref, kind: .task))])
        #expect(embed.contains("data-kind=\"task\""))
        #expect(embed.contains("data-ref=\"\(ref.uuidString)\""))
        let table = BlockHTMLSerializer.html(
            for: [Block(kind: .table(rows: [TableRow(cells: [[InlineRun(text: "a")], [InlineRun(text: "b")]])]))]
        )
        #expect(table == "<table><tr><td>a</td><td>b</td></tr></table>")
    }
}
