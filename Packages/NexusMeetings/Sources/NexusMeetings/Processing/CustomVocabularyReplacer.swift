import Foundation

/// Deterministic, case-insensitive, word-boundary-aware text replacement pass for
/// custom vocabulary. This is the load-bearing enforcement of the custom-vocab
/// feature (spec §8): the WhisperKit prompt only *biases* the rarely-taken
/// fallback path, whereas this pass corrects every transcript regardless of which
/// provider produced it.
///
/// Guarantees (pinned by tests):
/// - **Empty list = identity.** No entries -> the input is returned unchanged.
/// - **Longest term first.** Entries are applied longest-term-first so that a
///   short term ("forge") can never corrupt a longer one ("threat forge").
/// - **Case-insensitive, diacritic-insensitive match; canonical replacement.**
///   The `replacement` spelling/casing is emitted verbatim regardless of how the
///   term appeared in the transcript.
/// - **Word-boundary aware.** A term only matches when flanked by non-alphanumeric
///   boundaries, so "forge" does not rewrite the inside of "forged"/"reinforge".
public struct CustomVocabularyReplacer: Sendable {
    private struct CompiledEntry {
        let foldedTerm: String
        let replacement: String
    }

    private let entries: [CompiledEntry]

    public init(_ entries: [CustomVocabularyEntry]) {
        self.entries =
            entries
            .compactMap { entry -> CompiledEntry? in
                let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
                let replacement = entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
                guard term.isEmpty == false else { return nil }
                return CompiledEntry(foldedTerm: Self.fold(term), replacement: replacement)
            }
            // Longest term first so overlapping terms resolve to the longest match
            // (e.g. "threat forge" wins over "forge").
            .sorted { $0.foldedTerm.count > $1.foldedTerm.count }
    }

    /// Whether this replacer would ever change any input. An empty (or all-blank)
    /// vocabulary is a no-op and can be skipped entirely by callers.
    public var isEmpty: Bool { entries.isEmpty }

    /// Applies the vocabulary to a single string. Empty list returns the input
    /// unchanged (identity). Replacements are applied sequentially, longest term
    /// first; each pass scans the *current* text so a longer match consumes the
    /// region before a shorter sub-term can.
    public func apply(to text: String) -> String {
        guard entries.isEmpty == false, text.isEmpty == false else { return text }
        var result = text
        for entry in entries {
            result = Self.replace(
                foldedTerm: entry.foldedTerm,
                with: entry.replacement,
                in: result
            )
        }
        return result
    }

    /// Applies the vocabulary to each segment's text, returning corrected
    /// segments (timings/speaker untouched). Used before re-rendering
    /// `transcriptText` so `segmentsJSON`, the transcript, and downstream
    /// summary/action-items all share the corrected spelling.
    public func apply(to segments: [MeetingSpeakerSegment]) -> [MeetingSpeakerSegment] {
        guard entries.isEmpty == false else { return segments }
        return segments.map { segment in
            MeetingSpeakerSegment(
                startMs: segment.startMs,
                endMs: segment.endMs,
                speaker: segment.speaker,
                text: apply(to: segment.text)
            )
        }
    }

    // MARK: - Matching

    /// Word-boundary, case/diacritic-insensitive replacement of a single folded
    /// term. Matches on a folded copy of the text (so casing/diacritics don't
    /// affect detection) while splicing the canonical `replacement` into the
    /// *original* text at the matched range (so untouched text keeps its casing).
    private static func replace(foldedTerm: String, with replacement: String, in text: String) -> String {
        let original = Array(text)
        let folded = Array(fold(text))
        // Folding is per-character (diacritic + case) so it preserves index
        // alignment with the original array; guard defensively regardless.
        guard folded.count == original.count else {
            return naiveReplace(foldedTerm: foldedTerm, with: replacement, in: text)
        }

        let needle = Array(foldedTerm)
        guard needle.isEmpty == false, needle.count <= folded.count else { return text }

        var output: [Character] = []
        output.reserveCapacity(original.count)
        var index = 0
        while index < folded.count {
            let isWholeWordMatch =
                matches(needle: needle, in: folded, at: index)
                && isBoundary(folded, before: index)
                && isBoundary(folded, after: index + needle.count - 1)
            if isWholeWordMatch {
                output.append(contentsOf: replacement)
                index += needle.count
            } else {
                output.append(original[index])
                index += 1
            }
        }
        return String(output)
    }

    private static func matches(needle: [Character], in haystack: [Character], at start: Int) -> Bool {
        guard start + needle.count <= haystack.count else { return false }
        for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
            return false
        }
        return true
    }

    /// A match boundary holds when the character just outside the match is not
    /// alphanumeric (so we only rewrite whole words, never substrings of a word).
    private static func isBoundary(_ characters: [Character], before index: Int) -> Bool {
        guard index > 0 else { return true }
        return characters[index - 1].isLetterOrNumber == false
    }

    private static func isBoundary(_ characters: [Character], after index: Int) -> Bool {
        let next = index + 1
        guard next < characters.count else { return true }
        return characters[next].isLetterOrNumber == false
    }

    /// Fallback when per-character folding changes the string length (extremely
    /// rare for the diacritic+case fold). Plain case-insensitive scan with the
    /// same boundary rule, operating on the original string's scalars.
    private static func naiveReplace(foldedTerm: String, with replacement: String, in text: String) -> String {
        var result = text
        var searchRange = result.startIndex..<result.endIndex
        while let found = result.range(
            of: foldedTerm,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchRange
        ) {
            let beforeOK =
                found.lowerBound == result.startIndex
                || result[result.index(before: found.lowerBound)].isLetterOrNumber == false
            let afterOK =
                found.upperBound == result.endIndex
                || result[found.upperBound].isLetterOrNumber == false
            if beforeOK, afterOK {
                result.replaceSubrange(found, with: replacement)
                let resumeOffset =
                    result.distance(from: result.startIndex, to: found.lowerBound)
                    + replacement.count
                let resume = result.index(result.startIndex, offsetBy: resumeOffset)
                searchRange = resume..<result.endIndex
            } else {
                searchRange = found.upperBound..<result.endIndex
            }
            if searchRange.isEmpty { break }
        }
        return result
    }

    private static func fold(_ text: String) -> String {
        text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}

extension Character {
    fileprivate var isLetterOrNumber: Bool { isLetter || isNumber }
}
