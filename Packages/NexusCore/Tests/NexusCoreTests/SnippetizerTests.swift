import Foundation
import Testing

@testable import NexusCore

@Test func snippetizer_emptyText_returnsEmpty() {
    #expect(Snippetizer.snippet(query: "foo", text: "", radius: 20).isEmpty)
}

@Test func snippetizer_emptyQuery_returnsTextPrefix() {
    let text = "lorem ipsum dolor sit amet"
    let s = Snippetizer.snippet(query: "", text: text, radius: 10)
    #expect(s.hasPrefix("lorem"))
}

@Test func snippetizer_matchAtStart_returnsLeadingWindow() {
    let text = "hello world how are you"
    let s = Snippetizer.snippet(query: "hello", text: text, radius: 8)
    #expect(s.contains("hello world"))
    #expect(!s.hasPrefix("…"))
}

@Test func snippetizer_matchInMiddle_addsLeadingAndTrailingEllipsis() {
    let text = "this is a long text with the word target somewhere in the middle of it"
    let s = Snippetizer.snippet(query: "target", text: text, radius: 10)
    #expect(s.contains("target"))
    #expect(s.hasPrefix("…"))
    #expect(s.hasSuffix("…"))
}

@Test func snippetizer_matchIsCaseInsensitiveAndDiacriticInsensitive() {
    let text = "Pierwszy tekst, ksiazka jest tutaj."
    let s = Snippetizer.snippet(query: "książka", text: text, radius: 6)
    #expect(s.contains("ksiazka"))
}

@Test func snippetizer_textWithDiacritics_outputPreservesThem() {
    // Common case: user types a query without diacritics, but the indexed text has them.
    // Snippet output must keep the original diacritics intact.
    let text = "Pierwszy tekst, książka jest tutaj."
    let s = Snippetizer.snippet(query: "ksiazka", text: text, radius: 6)
    #expect(s.contains("książka"))
}

@Test func snippetizer_noMatch_returnsTextPrefixUpToRadius() {
    let text = "lorem ipsum dolor sit amet consectetur"
    let s = Snippetizer.snippet(query: "missing", text: text, radius: 10)
    #expect(s.hasPrefix("lorem"))
    #expect(s.count <= text.count)
}
