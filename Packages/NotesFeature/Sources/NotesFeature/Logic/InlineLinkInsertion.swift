import Foundation
import NexusCore

/// Pure helpers for inline wikilink insertion in the staged plain-text editor
/// (spec §5/§9, GAP #6). The text-bearing block editors bind to a flat plain-text
/// draft; these functions detect a typed `[[` trigger in that draft and splice a
/// `.link` run in place of the trigger token, or wrap a selected substring as a
/// link. The chosen target is always stored by **id** (`.link(ref:)`), never by
/// title — rename-safe (spec §9). The reconciler mirrors the `.link(ref:)` run as a
/// `mentions` edge on the next `updateContent`.
///
/// Why string-level (not run-level): the staged editor already collapses a block to
/// plain text on edit (`InlineRunRendering.runs(fromPlainText:)`), so the draft is
/// the working source. Splicing produces a 1–3 run array (plain prefix, link, plain
/// suffix) that persists through the existing `BlockListOps.setRuns` path.
public enum InlineLinkInsertion {

    /// A detected `[[` autocomplete trigger: the query typed after the opener and the
    /// half-open character range (in the draft) covering `[[` + query.
    public struct Trigger: Equatable, Sendable {
        /// The text typed after `[[` (may be empty just after typing `[[`).
        public var query: String
        /// Character range of the whole `[[query` token in the draft.
        public var range: Range<Int>

        public init(query: String, range: Range<Int>) {
            self.query = query
            self.range = range
        }
    }

    /// Detect a *trailing* `[[` autocomplete trigger in `draft`: an unclosed `[[`
    /// whose query runs to the end of the string. Returns nil when there is no open
    /// `[[`, when the most recent `[[` is already closed by `]]`, or when the query
    /// would span a newline (a trigger is a single-line token). Trailing-only is the
    /// compose-at-end UX; mid-caret insertion needs a selection API the staged
    /// `TextField` doesn't expose.
    public static func detectTrigger(in draft: String) -> Trigger? {
        let scalars = Array(draft)
        // Find the last `[[` opener.
        var opener: Int?
        var index = scalars.count - 2
        while index >= 0 {
            if scalars[index] == "[", scalars[index + 1] == "[" {
                opener = index
                break
            }
            index -= 1
        }
        guard let start = opener else { return nil }
        let queryChars = scalars[(start + 2)...]
        // A trailing trigger's query must not contain a closer or a newline.
        if queryChars.contains("\n") { return nil }
        if containsClosingBrackets(Array(queryChars)) { return nil }
        return Trigger(query: String(queryChars), range: start..<scalars.count)
    }

    /// `]]` anywhere in the query means the wikilink is already closed (the user
    /// finished it), so it is not an open trigger.
    private static func containsClosingBrackets(_ chars: [Character]) -> Bool {
        guard chars.count >= 2 else { return false }
        for offset in 0..<(chars.count - 1) where chars[offset] == "]" && chars[offset + 1] == "]" {
            return true
        }
        return false
    }

    /// Replace the `[[query` token (`trigger.range`) in `draft` with a single
    /// `.link(ref:)` run titled by the candidate, returning the block's full new run
    /// list: `[plain prefix?, link, plain suffix?]` with empty plain runs dropped.
    public static func splice(
        draft: String,
        trigger: Trigger,
        candidate: LinkCandidate
    ) -> [InlineRun] {
        let scalars = Array(draft)
        let prefix = String(scalars[..<trigger.range.lowerBound])
        let suffix = String(scalars[trigger.range.upperBound...])
        return assemble(prefix: prefix, title: candidate.title, ref: candidate.id, suffix: suffix)
    }

    /// Turn the substring `range` of `text` into a `.link(ref:)` run titled by the
    /// candidate (the candidate's title replaces the selected text — the link must
    /// store by id, and a selection of arbitrary text becomes the link label). A
    /// range outside the bounds is clamped; an empty/invalid range links at that
    /// point with the candidate title.
    public static func wrapSelection(
        text: String,
        range: Range<Int>,
        candidate: LinkCandidate
    ) -> [InlineRun] {
        let scalars = Array(text)
        let lower = max(0, min(range.lowerBound, scalars.count))
        let upper = max(lower, min(range.upperBound, scalars.count))
        let prefix = String(scalars[..<lower])
        let suffix = String(scalars[upper...])
        return assemble(prefix: prefix, title: candidate.title, ref: candidate.id, suffix: suffix)
    }

    private static func assemble(
        prefix: String,
        title: String,
        ref: UUID,
        suffix: String
    ) -> [InlineRun] {
        var runs: [InlineRun] = []
        if !prefix.isEmpty { runs.append(InlineRun(text: prefix)) }
        runs.append(InlineRun(text: title, marks: [.link(ref: ref, href: nil)]))
        if !suffix.isEmpty { runs.append(InlineRun(text: suffix)) }
        return runs
    }
}
