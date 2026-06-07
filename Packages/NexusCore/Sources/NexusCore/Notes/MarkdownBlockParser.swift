import Foundation

/// Parses Markdown into a `Note`'s canonical `[Block]` content (spec §11, core
/// scope — feeds the MCP write path, paste-as-markdown, and the round-trip
/// contract). Reverses `BlockMarkdownSerializer`; the pair forms a markdown
/// fixpoint for supported syntax (spec §17).
///
/// Deliberate placeholders the reconciler (out of scope here) later resolves:
/// - `todo`: `taskRef` is non-optional on the frozen `Block` model, but `- [ ]`
///   carries no UUID. The parser mints a fresh placeholder UUID; the reconciler
///   binds/creates the real `TaskItem`. (Spec §7 prose says "todo bez taskRef" —
///   the frozen model is non-optional, so the model wins; see handoff notes.)
/// - `embed` (`![[id]]`): markdown carries the id but not the `ItemKind`; the
///   parser defaults `kind` to `.note` and the reconciler corrects it.
/// - `link` wikilinks (`[[title]]`): stored as `link(ref: nil, href: nil)` with
///   the title as the run text — a pending-by-name link the reconciler resolves.
///
/// Block ids are freshly minted (markdown carries none). Round-trip identity is a
/// **markdown-string** fixpoint, not block identity.
///
/// CONTRACT — body only, no frontmatter: `parse` consumes the Markdown **body**
/// of a note, not a full frontmatter'd document. It does NOT recognize a YAML
/// `---` frontmatter fence — a leading `---` line is parsed as a `divider`. The
/// MCP write path (spec §12) passes `title`/`role`/`tags` as separate params and
/// only the body here; a caller holding a whole exported document must strip the
/// frontmatter first (e.g. `MarkdownFrontmatterCoder.decode(_:).body`) before
/// calling `parse`.
public enum MarkdownBlockParser {
    public static func parse(_ markdown: String) -> [Block] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [Block] = []
        var index = 0

        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)

            // Blank lines separate blocks; skip them.
            if trimmed.isEmpty {
                index += 1
                continue
            }

            // Multi-line blocks (fenced code, pipe table) consume a span.
            if let span = multiLineBlock(lines, at: index) {
                blocks.append(span.block)
                index += span.consumed
                continue
            }

            // Everything else is a single line.
            blocks.append(singleLineBlock(trimmed))
            index += 1
        }

        return blocks
    }

    // MARK: - Block dispatch

    private struct BlockSpan {
        var block: Block
        var consumed: Int
    }

    /// Parse a block that may span multiple lines (fenced code, pipe table).
    /// Returns `nil` when the line at `index` starts no such block.
    private static func multiLineBlock(_ lines: [String], at index: Int) -> BlockSpan? {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            return fencedCode(lines, at: index)
        }
        if startsTable(lines, at: index) {
            return table(lines, at: index)
        }
        return nil
    }

    /// A pipe row immediately followed by a `---|---` separator row.
    private static func startsTable(_ lines: [String], at index: Int) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard isTableRow(trimmed), index + 1 < lines.count else { return false }
        return isTableSeparator(lines[index + 1].trimmingCharacters(in: .whitespaces))
    }

    private static func fencedCode(_ lines: [String], at index: Int) -> BlockSpan {
        let opener = lines[index].trimmingCharacters(in: .whitespaces)
        let language = String(opener.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        var cursor = index + 1
        while cursor < lines.count, lines[cursor].trimmingCharacters(in: .whitespaces) != "```" {
            codeLines.append(lines[cursor])
            cursor += 1
        }
        cursor += 1  // consume the closing fence (or run past the end)
        let block = Block(
            kind: .code(
                language: language.isEmpty ? nil : language,
                text: codeLines.joined(separator: "\n")
            )
        )
        return BlockSpan(block: block, consumed: cursor - index)
    }

    private static func table(_ lines: [String], at index: Int) -> BlockSpan {
        var rows: [TableRow] = [tableRow(lines[index].trimmingCharacters(in: .whitespaces))]
        var cursor = index + 2  // header + separator
        while cursor < lines.count {
            let next = lines[cursor].trimmingCharacters(in: .whitespaces)
            guard isTableRow(next) else { break }
            rows.append(tableRow(next))
            cursor += 1
        }
        return BlockSpan(block: Block(kind: .table(rows: rows)), consumed: cursor - index)
    }

    /// Classify a single trimmed line into its block. Falls back to a paragraph.
    private static func singleLineBlock(_ trimmed: String) -> Block {
        if trimmed == "---" {
            return Block(kind: .divider)
        }
        if let ref = embedRef(in: trimmed) {
            return Block(kind: .embed(ref: ref, kind: .note))
        }
        if let asset = imageAsset(in: trimmed) {
            return Block(kind: .image(ref: nil, asset: asset))
        }
        if let parsed = heading(in: trimmed) {
            return Block(kind: .heading(level: parsed.level, runs: parseInline(parsed.rest)))
        }
        if let rest = todoBody(in: trimmed) {
            return Block(kind: .todo(taskRef: UUID(), runs: parseInline(rest)))
        }
        if trimmed.hasPrefix("- ") {
            return Block(kind: .bulleted(runs: parseInline(String(trimmed.dropFirst(2)))))
        }
        if let rest = numberedBody(in: trimmed) {
            return Block(kind: .numbered(runs: parseInline(rest)))
        }
        if trimmed.hasPrefix("> ") {
            return Block(kind: .quote(runs: parseInline(String(trimmed.dropFirst(2)))))
        }
        return Block(kind: .paragraph(runs: parseInline(trimmed)))
    }

    // MARK: - Block-line helpers

    private static func heading(in line: String) -> (level: Int, rest: String)? {
        var level = 0
        let chars = Array(line)
        while level < chars.count, chars[level] == "#" { level += 1 }
        guard level >= 1, level <= 6, level < chars.count, chars[level] == " " else {
            return nil
        }
        let rest = String(chars[(level + 1)...])
        return (level, rest)
    }

    private static func todoBody(in line: String) -> String? {
        guard line.hasPrefix("- [") else { return nil }
        let markers = ["- [ ] ", "- [x] ", "- [X] "]
        for marker in markers where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count))
        }
        return nil
    }

    private static func numberedBody(in line: String) -> String? {
        // `<digits>. <rest>`
        guard let dotRange = line.range(of: ". ") else { return nil }
        let prefix = line[line.startIndex..<dotRange.lowerBound]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        return String(line[dotRange.upperBound...])
    }

    private static func embedRef(in line: String) -> UUID? {
        guard line.hasPrefix("![["), line.hasSuffix("]]") else { return nil }
        let inner = String(line.dropFirst(3).dropLast(2))
        return UUID(uuidString: inner)
    }

    private static func imageAsset(in line: String) -> String? {
        guard line.hasPrefix("!["), let open = line.range(of: "]("),
            line.hasSuffix(")")
        else { return nil }
        // Must be `![...](...)` with nothing trailing the closing paren.
        let asset = String(line[open.upperBound..<line.index(before: line.endIndex)])
        return asset
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        return cellStrings(line).allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func tableRow(_ line: String) -> TableRow {
        TableRow(cells: cellStrings(line).map { parseInline($0.trimmingCharacters(in: .whitespaces)) })
    }

    /// Split `| a | b |` into `["a", "b"]` (drops the leading/trailing empties).
    private static func cellStrings(_ line: String) -> [String] {
        var parts = line.components(separatedBy: "|")
        if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            parts.removeFirst()
        }
        if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            parts.removeLast()
        }
        return parts
    }

    // MARK: - Inline parsing

    /// Inline state machine over a flat run model. A run carries a *set* of marks
    /// (`***x***` → `[bold, italic]`). Supported delimiters: `**` bold, `*`
    /// italic, `~~` strike, `` ` `` code, `[[title]]` wikilink, `[text](url)`
    /// link. Not CommonMark-complete — overlapping/ambiguous emphasis is out of
    /// scope (documented "≈ identity for supported syntax").
    static func parseInline(_ text: String) -> [InlineRun] {
        var runs: [InlineRun] = []
        let scalars = Array(text)
        var plain = ""
        var index = 0

        func flushPlain() {
            if !plain.isEmpty {
                runs.append(InlineRun(text: plain))
                plain = ""
            }
        }

        while index < scalars.count {
            if let token = inlineToken(scalars, at: index) {
                flushPlain()
                runs.append(contentsOf: token.runs)
                index = token.next
                continue
            }
            plain.append(scalars[index])
            index += 1
        }

        flushPlain()
        return runs.isEmpty ? [InlineRun(text: "")] : runs
    }

    private struct InlineToken {
        var runs: [InlineRun]
        var next: Int
    }

    /// Try to consume one inline token (mark span or link) starting at `index`.
    /// Returns `nil` if the position is plain text. Order matters: `***` before
    /// `**`/`*`, and wikilink `[[` before plain `[`.
    private static func inlineToken(_ scalars: [Character], at index: Int) -> InlineToken? {
        // Inline code: `…` (no nested marks inside).
        if scalars[index] == "`", let close = findClose(scalars, from: index + 1, marker: "`") {
            let inner = String(scalars[(index + 1)..<close])
            return InlineToken(runs: [InlineRun(text: inner, marks: [.code])], next: close + 1)
        }
        // Bold+italic: ***…*** (must precede `**`/`*` — the serializer emits
        // `***x***` for any run carrying both marks).
        if let close = closeOf("***", scalars, index) {
            let inner = parseInline(String(scalars[(index + 3)..<close]))
            return InlineToken(runs: addMark(.bold, to: addMark(.italic, to: inner)), next: close + 3)
        }
        if let close = closeOf("**", scalars, index) {
            let inner = parseInline(String(scalars[(index + 2)..<close]))
            return InlineToken(runs: addMark(.bold, to: inner), next: close + 2)
        }
        if let close = closeOf("~~", scalars, index) {
            let inner = parseInline(String(scalars[(index + 2)..<close]))
            return InlineToken(runs: addMark(.strike, to: inner), next: close + 2)
        }
        // Italic: *…* (single star, not part of `**`).
        if scalars[index] == "*", let close = findClose(scalars, from: index + 1, marker: "*") {
            let inner = parseInline(String(scalars[(index + 1)..<close]))
            return InlineToken(runs: addMark(.italic, to: inner), next: close + 1)
        }
        // Wikilink: [[title]]
        if let close = closeOf("[[", scalars, index, closeDelimiter: "]]") {
            let title = String(scalars[(index + 2)..<close])
            return InlineToken(runs: [InlineRun(text: title, marks: [.link(ref: nil, href: nil)])], next: close + 2)
        }
        // Link: [text](href)
        if scalars[index] == "[", let parsed = parseLink(scalars, from: index) {
            let run = InlineRun(text: parsed.text, marks: [.link(ref: nil, href: parsed.href)])
            return InlineToken(runs: [run], next: parsed.next)
        }
        return nil
    }

    /// If `scalars` opens with `open` at `index`, return the start index of the
    /// matching closing delimiter (defaults to `open`).
    private static func closeOf(
        _ open: String,
        _ scalars: [Character],
        _ index: Int,
        closeDelimiter: String? = nil
    ) -> Int? {
        guard matches(scalars, index, open) else { return nil }
        let close = closeDelimiter ?? open
        return findCloseDelimiter(scalars, from: index + open.count, delimiter: close)
    }

    private static func addMark(_ mark: Mark, to runs: [InlineRun]) -> [InlineRun] {
        runs.map { run in
            var marks = run.marks
            if !marks.contains(mark) { marks.append(mark) }
            return InlineRun(text: run.text, marks: marks)
        }
    }

    private static func matches(_ scalars: [Character], _ index: Int, _ delimiter: String) -> Bool {
        let chars = Array(delimiter)
        guard index + chars.count <= scalars.count else { return false }
        for offset in 0..<chars.count where scalars[index + offset] != chars[offset] {
            return false
        }
        return true
    }

    /// Find the next single-character `marker` at or after `from`, not immediately
    /// repeated (so a lone `*` doesn't match the first star of `**`).
    private static func findClose(_ scalars: [Character], from: Int, marker: Character) -> Int? {
        var index = from
        while index < scalars.count {
            if scalars[index] == marker {
                // For single-char markers, reject a doubled delimiter (that's a
                // different token, e.g. `**`).
                if index + 1 < scalars.count, scalars[index + 1] == marker {
                    index += 2
                    continue
                }
                return index
            }
            index += 1
        }
        return nil
    }

    private static func findCloseDelimiter(_ scalars: [Character], from: Int, delimiter: String) -> Int? {
        var index = from
        while index < scalars.count {
            if matches(scalars, index, delimiter) {
                return index
            }
            index += 1
        }
        return nil
    }

    private struct ParsedLink {
        var text: String
        var href: String
        var next: Int
    }

    private static func parseLink(_ scalars: [Character], from: Int) -> ParsedLink? {
        // [text](href)
        guard scalars[from] == "[" else { return nil }
        guard let textClose = findClose(scalars, from: from + 1, marker: "]") else { return nil }
        guard textClose + 1 < scalars.count, scalars[textClose + 1] == "(" else { return nil }
        guard let hrefClose = findClose(scalars, from: textClose + 2, marker: ")") else { return nil }
        let text = String(scalars[(from + 1)..<textClose])
        let href = String(scalars[(textClose + 2)..<hrefClose])
        return ParsedLink(text: text, href: href, next: hrefClose + 1)
    }
}
