import Foundation

/// Single source of truth for the OCR / image-attachment marker format that
/// `AgentRuntime` prepends to a user message before persisting it into
/// `AgentMessage.content`.
///
/// Why this exists: the agent is multi-turn over a sliding context window, so
/// the OCR-extracted text MUST be persisted into history (a text model can't
/// re-read image bytes on turn N+1). Design A is intentional and correct — see
/// `project-phase1l-ocr-history-ui-leak`. The side effect is that
/// `MessageBubbleView` would render the raw prepended markers in the user's own
/// chat bubble.
///
/// `userFacingText(_:)` is the **interim** cosmetic fix (LabKit Phase1l#4): it
/// strips the leading marker blocks at render time so the bubble shows what the
/// user actually typed. The proper fix is a V8 schema split
/// (`content` vs `attachmentContext`); until then, export/audit paths still see
/// the prepended form — this only affects the chat-bubble render.
///
/// The producer (`AgentRuntimeOCR.extractOCRBlocks`) builds blocks via
/// `ocrBlock(for:)` / `lowConfidenceHint`, so the format lives in exactly one
/// place and the stripper cannot drift from it.
enum AgentOCRMarker {
    /// Opening of a high-confidence OCR block: `[Image content extracted via OCR:\n`.
    static let ocrBlockPrefix = "[Image content extracted via OCR:\n"
    /// Closing of a high-confidence OCR block: `\n]`.
    static let ocrBlockSuffix = "\n]"
    /// Fixed marker for low-confidence / failed extraction.
    static let lowConfidenceHint =
        "[Image attached — text extraction confidence low; describe what you see if needed.]"

    /// The exact high-confidence OCR block string as persisted.
    static func ocrBlock(for text: String) -> String {
        ocrBlockPrefix + text + ocrBlockSuffix
    }

    /// Strips leading OCR / attachment marker blocks that `AgentRuntime`
    /// prepended (blocks are joined with `\n`, then `\n` + the original user
    /// message). Returns the text the user actually typed.
    ///
    /// Fail-safe: anything that does not match the exact marker shape is
    /// returned untouched — never strips legitimate user content that merely
    /// contains the phrase.
    static func userFacingText(_ content: String) -> String {
        var rest = Substring(content)
        while true {
            if rest.hasPrefix(ocrBlockPrefix) {
                let afterPrefix = rest.index(rest.startIndex, offsetBy: ocrBlockPrefix.count)
                let scan = rest[afterPrefix...]
                if let term = scan.range(of: ocrBlockSuffix + "\n") {
                    // `…\n]\n` — multi-line OCR text kept intact; continue past it.
                    rest = rest[term.upperBound...]
                    continue
                } else if scan.hasSuffix(ocrBlockSuffix) {
                    // Trailing block, no user text after it (image-only turn).
                    return ""
                } else {
                    break  // malformed — leave untouched
                }
            } else if rest.hasPrefix(lowConfidenceHint) {
                let afterHint = rest.index(rest.startIndex, offsetBy: lowConfidenceHint.count)
                let scan = rest[afterHint...]
                if scan.hasPrefix("\n") {
                    rest = rest[rest.index(after: afterHint)...]
                    continue
                } else if scan.isEmpty {
                    return ""
                } else {
                    break
                }
            } else {
                break
            }
        }
        return String(rest)
    }
}
