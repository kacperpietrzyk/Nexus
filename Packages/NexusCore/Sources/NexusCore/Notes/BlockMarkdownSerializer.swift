import Foundation

/// Serializes a `Note`'s `[Block]` content to Markdown (spec §11).
///
/// Anti-lock-in (CLAUDE.md: "markdown export must always be possible") and the
/// agent/MCP write path: `MarkdownBlockParser` reverses this, and the pair forms
/// a **markdown fixpoint** — `serialize(parse(md)) == md` for supported syntax
/// (round-trip contract, spec §17).
///
/// Syntax mapping (must stay in lockstep with `MarkdownBlockParser`):
/// - `# … ######`  → heading(level)
/// - `- [ ] `       → todo            - `- `       → bulleted
/// - `1. `          → numbered         - `> `       → quote
/// - fenced ``` ``` → code             - `---`      → divider
/// - `![[id]]`      → embed            - `| a | b |` → table
/// - `**`/`*`/`` ` ``/`~~` → marks     - `[[t]]`/`[t](url)` → link
public enum BlockMarkdownSerializer {
    public struct Options: Sendable, Equatable {
        public var includeTaskRefs: Bool

        public init(includeTaskRefs: Bool = false) {
            self.includeTaskRefs = includeTaskRefs
        }

        public static let plain = Options()
        public static let mcpRoundTrip = Options(includeTaskRefs: true)
    }

    public static func markdown(for blocks: [Block], options: Options = .plain) -> String {
        var out = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 {
                // Consecutive list-type blocks form a *tight* list (single
                // newline) — the conventional form an agent/paste produces and the
                // one the line-based parser re-reads identically. Every other
                // block boundary gets a blank line.
                let previous = blocks[index - 1].kind
                let tight = isListType(previous) && isListType(block.kind)
                out += tight ? "\n" : "\n\n"
            }
            out += markdown(for: block, options: options)
        }
        return out
    }

    private static func isListType(_ kind: BlockKind) -> Bool {
        switch kind {
        case .bulleted, .numbered, .todo: return true
        default: return false
        }
    }

    private static func markdown(for block: Block, options: Options) -> String {
        switch block.kind {
        case .paragraph(let runs):
            return escapeBlockPrefix(inlineMarkdown(runs))
        case .heading(let level, let runs):
            let clamped = min(max(level, 1), 6)
            return String(repeating: "#", count: clamped) + " " + inlineMarkdown(runs)
        case .todo(let taskRef, let runs):
            let body = "- [ ] " + inlineMarkdown(runs)
            guard options.includeTaskRefs else { return body }
            return body + " <!-- nexus-task:\(taskRef.uuidString) -->"
        case .bulleted(let runs):
            return "- " + inlineMarkdown(runs)
        case .numbered(let runs):
            return "1. " + inlineMarkdown(runs)
        case .quote(let runs):
            return "> " + inlineMarkdown(runs)
        case .code(let language, let text):
            return "```\(language ?? "")\n\(text)\n```"
        case .divider:
            return "---"
        case .image(_, let asset):
            return "![](\(asset ?? ""))"
        case .embed(let ref, _):
            // `kind` does not round-trip through `![[id]]`; the parser defaults it
            // and the reconciler corrects. Markdown fixpoint holds because neither
            // direction carries kind.
            return "![[\(ref.uuidString)]]"
        case .table(let rows):
            return tableMarkdown(rows)
        case .html(let raw):
            return raw
        }
    }

    private static func tableMarkdown(_ rows: [TableRow]) -> String {
        guard let header = rows.first else { return "" }
        let columnCount = header.cells.count
        var lines: [String] = []
        lines.append(rowMarkdown(header))
        // Markdown requires a header-separator row; TableRow carries no header
        // flag (model TODO) so the first row is treated as the header.
        lines.append("| " + Array(repeating: "---", count: max(columnCount, 1)).joined(separator: " | ") + " |")
        for row in rows.dropFirst() {
            lines.append(rowMarkdown(row))
        }
        return lines.joined(separator: "\n")
    }

    private static func rowMarkdown(_ row: TableRow) -> String {
        "| " + row.cells.map { inlineMarkdown($0) }.joined(separator: " | ") + " |"
    }

    private static func inlineMarkdown(_ runs: [InlineRun]) -> String {
        runs.map(inlineMarkdown(_:)).joined()
    }

    private static func inlineMarkdown(_ run: InlineRun) -> String {
        let marks = run.marks
        // Code spans and links/wikilinks are read back BYTE-LITERALLY by the
        // parser (their content is not re-inline-parsed), so their text must NOT
        // be escaped — escaping would leak backslashes into the literal payload.
        // Every other run's text IS re-parsed, so escape its inline metacharacters
        // (mirrored by the parser's `\X` unescape).
        let isLiteralContext =
            marks.contains(.code)
            || marks.contains { if case .link = $0 { return true } else { return false } }
        var text = isLiteralContext ? run.text : escapeInline(run.text)
        // Links wrap the (already mark-decorated) text. Apply emphasis markers
        // inner→outer in a fixed order so the same run always serializes the same
        // way: code innermost, then strike, italic, bold; link outermost.
        if marks.contains(.code) {
            text = "`\(text)`"
        }
        if marks.contains(.strike) {
            text = "~~\(text)~~"
        }
        if marks.contains(.italic) {
            text = "*\(text)*"
        }
        if marks.contains(.bold) {
            text = "**\(text)**"
        }
        for mark in marks {
            if case .link(_, let href) = mark {
                if let href {
                    text = "[\(text)](\(href))"
                } else {
                    // Wikilink (`href == nil`): a by-id ref (`ref != nil`) or a
                    // pending-by-name link (`ref == nil`, e.g. from a freshly
                    // parsed `[[…]]`). Either way the serializer has no context to
                    // resolve a ref back to a title, so it emits the cached run
                    // text as the wikilink target. The parser re-reads it as a
                    // by-name link (`link(ref: nil, href: nil)`), which is why the
                    // markdown fixpoint holds.
                    text = "[[\(text)]]"
                }
            }
        }
        return text
    }

    // MARK: - Escaping (keeps the round-trip a BLOCK fixpoint, not just a string)

    /// Backslash-escape the inline metacharacters the parser treats specially, so
    /// literal `\ * ` ~ [` in re-parsed run text survives the round-trip instead of
    /// being read back as emphasis/code/link delimiters. Mirrored by the parser's
    /// `\X` unescape. Backslash is escaped first (it is the escape char itself).
    private static func escapeInline(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\\", "*", "`", "~", "[":
                out.append("\\")
                out.append(character)
            default:
                out.append(character)
            }
        }
        return out
    }

    /// Prepend a backslash to a paragraph whose rendered line would otherwise be
    /// classified as a different block (heading/list/quote/divider/numbered, incl.
    /// their empty/bare forms). The parser drops the leading `\` via inline unescape
    /// and reads the line as a paragraph. Backtick-fence and `![…` lines are already
    /// neutralized by `escapeInline` (it escapes `` ` `` and `[`), so only the
    /// line-start-only sigils are handled here.
    private static func escapeBlockPrefix(_ rendered: String) -> String {
        // Numbered lines escape the DOT (punctuation), not the leading digit: the
        // parser's punctuation-only unescape would leave `\1` literal but reverses
        // `1\.` -> `1.`.
        if isNumberedPrefixed(rendered) || isBareNumbered(rendered) {
            return escapeNumberedDot(rendered)
        }
        // Every other trigger starts with a punctuation char (`#`/`-`/`>`), so a
        // single leading backslash round-trips cleanly through the unescape.
        return needsBlockPrefixEscape(rendered) ? "\\" + rendered : rendered
    }

    private static func needsBlockPrefixEscape(_ line: String) -> Bool {
        if line == "---" { return true }
        // Bare/empty marker forms a paragraph could otherwise be read as (the empty
        // bullet/quote serializations `- `/`> ` trim to these); `- [ ]` is covered
        // by the `- ` prefix.
        if line == "-" || line == ">" { return true }
        if line.hasPrefix("- ") || line.hasPrefix("> ") { return true }
        if isHeadingPrefixed(line) { return true }
        return false
    }

    /// Insert a backslash before the dot of a numbered line (`1. x` -> `1\. x`).
    private static func escapeNumberedDot(_ line: String) -> String {
        guard let dotIndex = digitsBeforeDot(line) else { return line }
        var result = line
        result.insert("\\", at: dotIndex)
        return result
    }

    /// `^#{1,6} ` — matches the parser's heading classifier (1–6 hashes then a space).
    private static func isHeadingPrefixed(_ line: String) -> Bool {
        var hashes = 0
        for character in line {
            if character == "#" {
                hashes += 1
                if hashes > 6 { return false }
            } else {
                return hashes >= 1 && character == " "
            }
        }
        return false
    }

    /// `^[0-9]+\. ` — matches the parser's numbered classifier (digits, dot, space).
    private static func isNumberedPrefixed(_ line: String) -> Bool {
        digitsBeforeDot(line).map { line.distance(from: line.startIndex, to: $0) > 0 && trailingDotSpace($0, in: line) }
            ?? false
    }

    /// `^[0-9]+\.$` — the bare/empty numbered form (`1.`), which trims off its space.
    private static func isBareNumbered(_ line: String) -> Bool {
        guard let dotIndex = digitsBeforeDot(line), line.distance(from: line.startIndex, to: dotIndex) > 0 else {
            return false
        }
        return line.index(after: dotIndex) == line.endIndex
    }

    /// Index of the `.` immediately following a run of leading digits, or nil.
    private static func digitsBeforeDot(_ line: String) -> String.Index? {
        var index = line.startIndex
        while index < line.endIndex, line[index].isNumber { index = line.index(after: index) }
        guard index < line.endIndex, line[index] == "." else { return nil }
        return index
    }

    private static func trailingDotSpace(_ dotIndex: String.Index, in line: String) -> Bool {
        let afterDot = line.index(after: dotIndex)
        return afterDot < line.endIndex && line[afterDot] == " "
    }
}
