import Foundation

/// Serializes a `Note`'s `[Block]` content to HTML (spec §11/§14).
///
/// Purpose: dense, readable context for the agent, share, and the `html(raw)`
/// render path. This is a **one-way** serializer — there is no HTML→Blocks
/// parser (the round-trip contract in spec §17 covers Markdown only).
///
/// Safety (§14): every piece of text that originates from note content is HTML-
/// escaped (`&`, `<`, `>`, `"`, `'`), including the contents of `code` blocks
/// and inline `code` runs. The **only** un-escaped passthrough is the
/// `html(raw)` block — that is the deliberate escape-hatch, sanitized later at
/// render time (WKWebView, JS off), not here.
public enum BlockHTMLSerializer {
    public static func html(for blocks: [Block]) -> String {
        blocks.map(html(for:)).joined(separator: "\n")
    }

    private static func html(for block: Block) -> String {
        switch block.kind {
        case .paragraph(let runs):
            return "<p>\(inlineHTML(runs))</p>"
        case .heading(let level, let runs):
            let clamped = min(max(level, 1), 6)
            return "<h\(clamped)>\(inlineHTML(runs))</h\(clamped)>"
        case .todo(_, let runs):
            // taskRef is intentionally not surfaced in HTML; the live task state
            // (checked/unchecked) is resolved by the renderer, not the serializer.
            return "<li><input type=\"checkbox\" disabled> \(inlineHTML(runs))</li>"
        case .bulleted(let runs):
            return "<ul><li>\(inlineHTML(runs))</li></ul>"
        case .numbered(let runs):
            return "<ol><li>\(inlineHTML(runs))</li></ol>"
        case .quote(let runs):
            return "<blockquote>\(inlineHTML(runs))</blockquote>"
        case .code(let language, let text):
            let langAttr = language.map { " class=\"language-\(escape($0))\"" } ?? ""
            return "<pre><code\(langAttr)>\(escape(text))</code></pre>"
        case .divider:
            return "<hr>"
        case .image(_, let asset):
            let src = asset.map(escape) ?? ""
            return "<img src=\"\(src)\">"
        case .embed(let ref, let kind):
            // Read-only transclusion placeholder; the live preview is resolved by
            // the renderer. Emit a stable, escaped marker carrying ref + kind.
            return "<div class=\"embed\" data-kind=\"\(escape(kind.rawValue))\" "
                + "data-ref=\"\(ref.uuidString)\"></div>"
        case .table(let rows):
            return tableHTML(rows)
        case .html(let raw):
            // The escape-hatch: passthrough, NOT escaped. Sanitized at render.
            return raw
        }
    }

    private static func tableHTML(_ rows: [TableRow]) -> String {
        guard !rows.isEmpty else { return "<table></table>" }
        let body = rows.map { row in
            let cells = row.cells.map { "<td>\(inlineHTML($0))</td>" }.joined()
            return "<tr>\(cells)</tr>"
        }.joined()
        return "<table>\(body)</table>"
    }

    private static func inlineHTML(_ runs: [InlineRun]) -> String {
        runs.map(inlineHTML(_:)).joined()
    }

    private static func inlineHTML(_ run: InlineRun) -> String {
        var html = escape(run.text)
        // Apply marks inner→outer in a deterministic order so the same run always
        // produces the same nesting. `code` wraps innermost; `link` outermost.
        for mark in orderedMarks(run.marks) {
            switch mark {
            case .code: html = "<code>\(html)</code>"
            case .bold: html = "<strong>\(html)</strong>"
            case .italic: html = "<em>\(html)</em>"
            case .strike: html = "<del>\(html)</del>"
            case .link(let ref, let href):
                if let href {
                    html = "<a href=\"\(escape(href))\">\(html)</a>"
                } else if let ref {
                    // Wikilink (by-id) with no URL: stable data-ref anchor.
                    html = "<a data-ref=\"\(ref.uuidString)\">\(html)</a>"
                }
            }
        }
        return html
    }

    /// Deterministic mark nesting order (innermost first). Independent of the
    /// order marks happen to appear in the stored run.
    private static func orderedMarks(_ marks: [Mark]) -> [Mark] {
        func rank(_ mark: Mark) -> Int {
            switch mark {
            case .code: return 0
            case .strike: return 1
            case .italic: return 2
            case .bold: return 3
            case .link: return 4
            }
        }
        return marks.sorted { rank($0) < rank($1) }
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }
}
