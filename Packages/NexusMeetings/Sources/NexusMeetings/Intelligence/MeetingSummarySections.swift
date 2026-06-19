import Foundation

/// Structured view over a meeting's persisted `summaryText`, parsed for the
/// Meetings/Notes screen (AI Summary paragraph + Decisions rows) and the Today
/// screen's MeetingIntel DTO. Pure parsing — no schema changes, no AI calls.
///
/// Real-world `summaryText` shapes this parser is designed around:
/// - **Native pipeline** (`MeetingPromptBuilder.summaryPrompt` default template):
///   `## TL;DR` (short paragraph), `## Key topics` (`-` bullets),
///   `## Decisions made` (`-` bullets). Action items are NOT in the summary —
///   they are extracted separately and linked as Tasks via `actionItemIDs`;
///   any action-item-looking text parsed here is supplementary display only.
/// - **Circleback import** (`CirclebackImporter` stores notes markdown verbatim):
///   `#### Przegląd` / `#### Overview` style level-4 headings, `*` bullets,
///   Polish/English content with inline `**bold**` markdown.
/// - **Custom templates / user edits** (`SummaryView` has a raw markdown editor):
///   arbitrary text — tolerated via fallbacks (preamble before the first heading
///   becomes the overview; text without any headings is treated wholesale as the
///   overview, with no decisions).
public struct MeetingSummarySections: Equatable, Sendable {
    /// A recognized non-overview, non-decisions section (e.g. "Key topics",
    /// "Następne kroki"). Items are bullet/number-stripped non-empty lines.
    public struct Section: Equatable, Sendable {
        public let title: String
        public let items: [String]

        public init(title: String, items: [String]) {
            self.title = title
            self.items = items
        }
    }

    /// First narrative paragraph/section: the body of the first heading whose
    /// title matches an overview keyword (TL;DR / Summary / Overview /
    /// Przegląd / Podsumowanie), else any preamble before the first heading,
    /// else — when the text has no headings at all — the whole text.
    /// Bullet/number prefixes are stripped from each line, so a bullet-style
    /// overview section (Circleback's `* …` lines) reads as plain paragraphs.
    public let overview: String?
    /// Bullet-stripped lines of every section whose heading matches a decisions
    /// keyword (Decision(s) / Decyzje / Ustalenia), in document order.
    public let decisions: [String]
    /// All remaining sections in document order; sections with no items are dropped.
    public let extraSections: [Section]

    public static let empty = MeetingSummarySections(overview: nil, decisions: [], extraSections: [])

    public init(overview: String?, decisions: [String], extraSections: [Section]) {
        self.overview = overview
        self.decisions = decisions
        self.extraSections = extraSections
    }

    public static func parse(summaryText: String?) -> MeetingSummarySections {
        guard let summaryText, summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .empty
        }

        let blocks = splitIntoSections(summaryText)

        // No headings at all → the whole text is the overview.
        guard blocks.contains(where: { $0.title != nil }) else {
            let text = joinedBody(blocks.flatMap(\.lines))
            return MeetingSummarySections(overview: text, decisions: [], extraSections: [])
        }

        var overview: String?
        var preamble: String?
        var decisions: [String] = []
        var extraSections: [Section] = []

        for block in blocks {
            guard let title = block.title else {
                preamble = joinedBody(block.lines)
                continue
            }
            let normalized = normalize(title)
            if overview == nil, overviewKeywords.contains(where: normalized.contains) {
                overview = joinedBody(block.lines)
            } else if decisionsKeywords.contains(where: normalized.contains) {
                decisions.append(contentsOf: itemLines(block.lines))
            } else {
                let items = itemLines(block.lines)
                if items.isEmpty == false {
                    extraSections.append(Section(title: title, items: items))
                }
            }
        }

        return MeetingSummarySections(
            overview: overview ?? preamble,
            decisions: decisions,
            extraSections: extraSections
        )
    }

    // MARK: - Internals

    private struct Block {
        let title: String?
        var lines: [String]
    }

    /// Keywords are matched against a lowercased, diacritic-folded heading title.
    private static let overviewKeywords = ["tl;dr", "tldr", "summary", "overview", "przeglad", "podsumowanie"]
    /// "decyzj" is an intentional stem: it matches the Polish inflections
    /// decyzje / decyzja / decyzji / decyzją from a single entry.
    private static let decisionsKeywords = ["decision", "decyzj", "ustalenia"]

    // Computed (not stored) because `Regex` is not `Sendable`; literals are cheap to build.
    /// Matches an ATX markdown heading (`#` … `######`), tolerating up to three
    /// leading spaces and optional trailing hashes.
    private static var headingRegex: Regex<(Substring, Substring)> { /^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$/ }
    /// Matches `-` / `*` / `•` / `+` bullets and `1.` / `1)` numbered prefixes.
    private static var bulletPrefixRegex: Regex<Substring> { /^\s*(?:[-*•+]\s+|\d{1,3}[.)]\s+)/ }

    private static func normalize(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func splitIntoSections(_ text: String) -> [Block] {
        let heading = headingRegex
        var blocks: [Block] = []
        var current = Block(title: nil, lines: [])
        for rawLine in text.components(separatedBy: .newlines) {
            if let match = rawLine.firstMatch(of: heading) {
                blocks.append(current)
                current = Block(title: String(match.1), lines: [])
            } else {
                current.lines.append(rawLine)
            }
        }
        blocks.append(current)
        return blocks
    }

    /// Non-empty lines with bullet/number markers stripped.
    private static func itemLines(_ lines: [String]) -> [String] {
        let bulletPrefix = bulletPrefixRegex
        return lines.compactMap { line in
            let stripped = line.replacing(bulletPrefix, with: "")
                .trimmingCharacters(in: .whitespaces)
            return stripped.isEmpty ? nil : stripped
        }
    }

    /// Section body as display text: bullet-stripped lines joined by newlines,
    /// `nil` when the body is empty.
    private static func joinedBody(_ lines: [String]) -> String? {
        let items = itemLines(lines)
        return items.isEmpty ? nil : items.joined(separator: "\n")
    }
}

/// Lightweight aggregate stats for the Meetings/Notes Insights panel, derived
/// from already-persisted `Meeting` fields (`durationSec`, `segmentsJSON`,
/// `transcriptText`). Pure aggregation — no AI calls.
public struct MeetingInsights: Equatable, Sendable {
    public struct SpeakerShare: Equatable, Sendable {
        public let speaker: String
        public let talkMs: Int
        /// Fraction of total talk time, in `0...1`.
        public let share: Double

        public init(speaker: String, talkMs: Int, share: Double) {
            self.speaker = speaker
            self.talkMs = talkMs
            self.share = share
        }
    }

    /// Compact `"1h 30m"` / `"5m"` / `"45s"` style duration, `nil` when unknown.
    public let durationText: String?
    /// Per-speaker talk share from transcript segments, sorted by talk time
    /// descending (ties alphabetical). Empty when segments carry no usable timing.
    public let speakerShares: [SpeakerShare]
    /// Whitespace-separated word count of the raw transcript.
    public let wordCount: Int
    /// Most frequent transcript terms: lowercased, at least three characters,
    /// stopwords removed, sorted by frequency descending (ties alphabetical),
    /// capped at five.
    public let topTerms: [String]

    public static let empty = MeetingInsights(durationText: nil, speakerShares: [], wordCount: 0, topTerms: [])

    public init(durationText: String?, speakerShares: [SpeakerShare], wordCount: Int, topTerms: [String]) {
        self.durationText = durationText
        self.speakerShares = speakerShares
        self.wordCount = wordCount
        self.topTerms = topTerms
    }

    public static func insights(
        durationSec: Int?,
        segments: [MeetingSpeakerSegment],
        transcriptText: String?,
        speakerNames: [String: String] = [:]
    ) -> MeetingInsights {
        let raw = transcriptText ?? ""
        // wordCount always reflects the full raw transcript so the metric is stable
        // regardless of whether segments are available.
        let rawWords =
            raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
        // topTerms: prefer clean segment text (no speaker labels / timestamps).
        // The Circleback-imported `transcriptText` shape is
        //   "[HH:MM:SS] Speaker Label\n<spoken text>\n"
        // so iterating lines and stripping the speaker-prefix misses the header
        // line entirely. Each MeetingSpeakerSegment.text is the spoken text only.
        // Fall back to the line-stripping path only when there are no segments.
        let termWords: [String]
        if segments.isEmpty == false {
            termWords =
                segments
                .map(\.text)
                .joined(separator: " ")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.isEmpty == false }
        } else {
            termWords =
                raw
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(spokenText(fromTranscriptLine:))
                .joined(separator: " ")
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.isEmpty == false }
        }
        return MeetingInsights(
            durationText: durationText(seconds: durationSec),
            speakerShares: speakerShares(from: segments, names: speakerNames),
            wordCount: rawWords.count,
            topTerms: topTerms(words: termWords)
        )
    }

    /// Drops a leading `"<Speaker>: "` label from a transcript line so the speaker
    /// name does not pollute topic extraction. A line counts as having a speaker
    /// prefix only when the text before the first `": "` is short (≤ 5 words) and
    /// label-like; otherwise the line is returned unchanged (a colon inside prose
    /// must not eat the sentence).
    static func spokenText(fromTranscriptLine line: Substring) -> String {
        guard let range = line.range(of: ": ") else { return String(line) }
        let label = line[line.startIndex..<range.lowerBound]
        let wordCount = label.split(separator: " ").count
        guard wordCount >= 1, wordCount <= 5 else { return String(line) }
        return String(line[range.upperBound...])
    }

    // MARK: - Internals

    private static let maxTopTerms = 5
    private static let minTermLength = 3

    /// Small, fixed stopword list. Transcripts are realistically English or
    /// Polish (see imported Circleback fixtures), so the list mixes the most
    /// common terms of both instead of doing language detection.
    ///
    /// Entries are stored in the same folded form produced by `foldForStopwords(_:)`:
    /// lowercased, `ł→l` replacement, then `.diacriticInsensitive` fold. Candidate
    /// terms are folded identically before lookup so e.g. "było" (real ł, not ASCII)
    /// matches "bylo". Note that `.diacriticInsensitive` alone does NOT remove ł
    /// because ł is a distinct letter in Polish, not a base letter with a diacritic.
    /// Terms shorter than `minTermLength` are dropped before this check.
    private static let stopwords: Set<String> = [
        // English
        "the", "and", "for", "are", "was", "were", "this", "that", "with", "from",
        "have", "has", "had", "not", "but", "you", "your", "our", "will", "would",
        "can", "could", "just", "about", "what", "which", "who", "there", "then",
        "than", "they", "them", "his", "her", "its", "all", "any", "been", "did",
        "does", "into", "more", "some", "very", "when", "where", "how", "also",
        // Polish (diacritic+ł folded)
        "nie", "jest", "sie", "jak", "ale", "dla", "czy", "tak", "byc", "byl",
        "byla", "bylo", "oraz", "lub", "tym", "tego", "ten", "tej", "juz", "tez",
        "wiec", "przez", "ktory", "ktora", "ktore", "bedzie", "mamy", "jako",
        "czyli", "tylko", "jego", "jej", "tam", "gdzie", "kiedy", "albo",
        // Polish fillers leaking from real transcripts (diacritic+ł folded)
        "zeby", "moze", "prostu", "wiem", "mozna", "bardzo", "troche", "jakby",
        "wlasnie", "znaczy", "dlatego", "teraz", "dobrze", "prosze", "wtedy",
        "jeszcze", "takie", "taki", "taka", "cos", "kogo", "sobie", "mnie",
        "takiego", "trzeba", "dobra", "dobry", "bylo", "byli", "aha", "wlasciwie",
        // English contractions folded to alphanumerics
        "youre", "dont", "thats", "iam", "weve", "well", "okay", "yeah",
    ]

    /// Folds a term for stopword comparison: lowercase → replace ł with l → diacritic strip.
    /// ł is a distinct Polish letter that `.diacriticInsensitive` does not remove,
    /// so we handle it explicitly. The caller keeps the original spelling for display.
    private static func foldForStopwords(_ term: String) -> String {
        term
            .replacingOccurrences(of: "ł", with: "l")
            .folding(options: .diacriticInsensitive, locale: nil)
    }

    private static func durationText(seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(remainder)s"
    }

    private static func speakerShares(
        from segments: [MeetingSpeakerSegment],
        names: [String: String] = [:]
    ) -> [SpeakerShare] {
        var talkMsBySpeaker: [String: Int] = [:]
        for segment in segments where segment.endMs > segment.startMs {
            let label = names[canonicalSpeakerKey(segment.speaker)] ?? segment.speaker
            talkMsBySpeaker[label, default: 0] += segment.endMs - segment.startMs
        }
        let totalMs = talkMsBySpeaker.values.reduce(0, +)
        guard totalMs > 0 else { return [] }
        return
            talkMsBySpeaker
            .map { SpeakerShare(speaker: $0.key, talkMs: $0.value, share: Double($0.value) / Double(totalMs)) }
            .sorted { lhs, rhs in
                if lhs.talkMs != rhs.talkMs { return lhs.talkMs > rhs.talkMs }
                return lhs.speaker < rhs.speaker
            }
    }

    private static func topTerms(words: [String]) -> [String] {
        // Counts are keyed by the diacritic+ł folded form so spelling variants like
        // "wdrożenie"/"wdrozenie" merge into one term; the first-seen original
        // spelling is kept for display.
        var counts: [String: (display: String, count: Int)] = [:]
        for word in words {
            let scalars = word.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            let term = String(String.UnicodeScalarView(scalars))
            guard term.count >= minTermLength else { continue }
            let folded = foldForStopwords(term)
            guard stopwords.contains(folded) == false else { continue }
            counts[folded, default: (display: term, count: 0)].count += 1
        }
        return
            counts
            .sorted { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count > rhs.value.count }
                return lhs.key < rhs.key
            }
            .prefix(maxTopTerms)
            .map(\.value.display)
    }
}
