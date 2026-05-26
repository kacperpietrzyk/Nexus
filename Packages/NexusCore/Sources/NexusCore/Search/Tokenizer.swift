import Foundation
import NaturalLanguage

/// Pure-function tokenizer used by `SearchIndex`. Word-segments via `NLTokenizer(unit: .word)`
/// (Polish + English aware), then lowercases each token and folds diacritics so that
/// "książka" and "ksiazka" produce identical tokens.
///
/// Stateless / `Sendable`. Cheap to call repeatedly — `NLTokenizer` is allocated per call,
/// which is fine for short strings (titles, snippets); if profiling later shows allocation
/// pressure, hoist into a thread-local.
public enum Tokenizer {
    public static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let raw = String(text[range])
            let folded =
                raw
                .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
                .lowercased()
            // NLTokenizer can yield empty tokens for some boundary cases; guard.
            if !folded.isEmpty {
                tokens.append(folded)
            }
            return true
        }
        return tokens
    }
}
