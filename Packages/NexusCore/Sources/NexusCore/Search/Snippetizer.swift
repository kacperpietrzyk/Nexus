import Foundation

/// Pure-function substring snippet builder.
///
/// Matching mirrors `Tokenizer` semantics: lowercase + diacritic-folded, but on a
/// single-pass folded copy of `text` so we can return character offsets back into the
/// **original** text (preserving casing and diacritics in the snippet).
public enum Snippetizer {
    public static func snippet(query: String, text: String, radius: Int) -> String {
        guard !text.isEmpty else { return "" }
        let folded =
            text
            .folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US_POSIX"))
            .lowercased()

        // Empty query → leading window of the original text, ellipsized if truncated.
        guard !query.isEmpty else {
            return prefixWindow(text: text, radius: radius)
        }

        // First matching query token (after tokenizing the query the same way as the index).
        let queryTokens = Tokenizer.tokenize(query)
        guard let firstToken = queryTokens.first else {
            return prefixWindow(text: text, radius: radius)
        }

        guard let foldedRange = folded.range(of: firstToken) else {
            return prefixWindow(text: text, radius: radius)
        }

        // `folded` and `text` have identical UTF-16 lengths because diacritic folding +
        // lowercasing don't change scalar count for the languages we care about.
        // We compute offsets in folded and map back via `String.Index` distance.
        let lower = folded.distance(from: folded.startIndex, to: foldedRange.lowerBound)
        let upper = folded.distance(from: folded.startIndex, to: foldedRange.upperBound)
        let count = text.count

        let windowStart = max(0, min(count, lower - radius))
        let windowEnd = max(windowStart, min(count, upper + radius))

        let startIdx = text.index(text.startIndex, offsetBy: windowStart)
        let endIdx = text.index(text.startIndex, offsetBy: windowEnd)
        var window = String(text[startIdx..<endIdx])

        if windowStart > 0 { window = "…" + window }
        if windowEnd < count { window += "…" }
        return window
    }

    private static func prefixWindow(text: String, radius: Int) -> String {
        let limit = min(radius * 2, text.count)
        let endIdx = text.index(text.startIndex, offsetBy: limit)
        var window = String(text[text.startIndex..<endIdx])
        if limit < text.count { window += "…" }
        return window
    }
}
