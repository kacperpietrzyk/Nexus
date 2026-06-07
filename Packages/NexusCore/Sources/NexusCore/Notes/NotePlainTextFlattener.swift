import Foundation

/// Flattens a `Note`'s `[Block]` content into the denormalized `plainText` cache
/// (spec §4.1/§6.4). This is the source for search / list / Watch, so it must be
/// *plain* text — no markdown sigils (`#`, `- [ ]`, `**`) that would pollute FTS
/// tokenization. Deliberately NOT `BlockMarkdownSerializer`, which emits markup.
///
/// Rules: emit the visible text of each block, one block per line.
/// - paragraph/heading/list/quote/todo → the run text.
/// - code → the raw code text.
/// - table → each cell's run text, cells space-joined, rows newline-joined.
/// - divider → nothing (no visible text).
/// - image → the `asset` locator if present (alt-ish), else nothing.
/// - embed → nothing (the embedded object indexes its own content; the link edge
///   leads search to it).
/// - html(raw) → the raw HTML verbatim (best-effort; stripping tags is YAGNI here).
///
/// Blank-producing blocks are dropped so the cache has no empty lines.
public enum NotePlainTextFlattener {
    public static func plainText(for blocks: [Block]) -> String {
        var lines: [String] = []
        for block in blocks {
            if let line = text(for: block.kind), !line.isEmpty {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func text(for kind: BlockKind) -> String? {
        switch kind {
        case .paragraph(let runs),
            .heading(_, let runs),
            .todo(_, let runs),
            .bulleted(let runs),
            .numbered(let runs),
            .quote(let runs):
            return runText(runs)
        case .code(_, let text):
            return text
        case .table(let rows):
            return
                rows
                .map { row in row.cells.map(runText(_:)).joined(separator: " ") }
                .joined(separator: "\n")
        case .image(_, let asset):
            return asset
        case .html(let raw):
            return raw
        case .divider, .embed:
            return nil
        }
    }

    private static func runText(_ runs: [InlineRun]) -> String {
        runs.map(\.text).joined()
    }
}
