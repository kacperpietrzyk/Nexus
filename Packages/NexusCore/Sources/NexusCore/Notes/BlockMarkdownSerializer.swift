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
            return inlineMarkdown(runs)
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
        var text = run.text
        // Links wrap the (already mark-decorated) text. Apply emphasis markers
        // inner→outer in a fixed order so the same run always serializes the same
        // way: code innermost, then strike, italic, bold; link outermost.
        let marks = run.marks
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
}
