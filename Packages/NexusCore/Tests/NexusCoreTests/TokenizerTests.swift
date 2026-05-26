import Foundation
import Testing

@testable import NexusCore

@Test func tokenizer_emptyString_returnsEmpty() {
    #expect(Tokenizer.tokenize("") == [])
    #expect(Tokenizer.tokenize("   ") == [])
}

@Test func tokenizer_simpleEnglish_lowercasesAndSplits() {
    #expect(Tokenizer.tokenize("Hello World") == ["hello", "world"])
}

@Test func tokenizer_polish_handlesDiacriticsAndCases() {
    // "Książka jest świetna" → expect ascii-folded lowercase tokens
    let tokens = Tokenizer.tokenize("Książka jest świetna")
    #expect(tokens == ["ksiazka", "jest", "swietna"])
}

@Test func tokenizer_polish_unfoldedQueryMatchesFoldedIndex() {
    // Both forms must produce identical token streams so a query "ksiazka"
    // hits an item indexed as "książka" (and vice versa).
    #expect(Tokenizer.tokenize("ksiazka") == Tokenizer.tokenize("książka"))
}

@Test func tokenizer_punctuationIsStripped() {
    let tokens = Tokenizer.tokenize("foo, bar! baz?")
    #expect(tokens == ["foo", "bar", "baz"])
}

@Test func tokenizer_numbersAreKept() {
    let tokens = Tokenizer.tokenize("Phase 0d Search")
    #expect(tokens.contains("phase"))
    #expect(tokens.contains("0d"))
    #expect(tokens.contains("search"))
}

@Test func tokenizer_mixedScripts_polishAndEnglish() {
    let tokens = Tokenizer.tokenize("Tworzę task: review code")
    #expect(tokens.contains("tworze"))
    #expect(tokens.contains("task"))
    #expect(tokens.contains("review"))
    #expect(tokens.contains("code"))
}
