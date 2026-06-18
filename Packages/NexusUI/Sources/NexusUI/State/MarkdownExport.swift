import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Cross-platform pasteboard write. macOS uses `NSPasteboard`, iOS uses
/// `UIPasteboard`; watchOS has no system pasteboard, so the call is a no-op
/// there (mirroring how other primitives degrade on watchOS).
public enum PasteboardCopy {
    /// Writes `string` to the general pasteboard.
    public static func string(_ string: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = string
        #endif
        // watchOS: no system pasteboard — intentional no-op.
    }
}

/// Pure Markdown builders for the common entity shape (title + body + metadata
/// lines). Modules pass their own already-formatted strings; these helpers only
/// assemble the canonical layout so copy-as-markdown reads the same everywhere.
///
/// All functions are pure `String -> String`, so they unit-test directly; the
/// side effect lives in `PasteboardCopy`.
public enum MarkdownExport {

    /// Formats one entity as Markdown:
    ///
    /// ```markdown
    /// # Title
    ///
    /// - Meta line 1
    /// - Meta line 2
    ///
    /// Body text…
    /// ```
    ///
    /// Empty `metadata` and empty `body` sections are omitted (no stray blank
    /// runs or dangling headings).
    ///
    /// - Parameters:
    ///   - title: heading text (rendered as an `# h1`). Whitespace-only titles
    ///     are dropped.
    ///   - body: free-form body markdown. Trailing whitespace is trimmed.
    ///   - metadata: short metadata lines rendered as a bullet list.
    public static func entity(
        title: String,
        body: String = "",
        metadata: [String] = []
    ) -> String {
        var blocks: [String] = []

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            blocks.append("# \(trimmedTitle)")
        }

        let metaLines =
            metadata
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !metaLines.isEmpty {
            blocks.append(metaLines.map { "- \($0)" }.joined(separator: "\n"))
        }

        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            blocks.append(trimmedBody)
        }

        return blocks.joined(separator: "\n\n")
    }

    /// Joins several entity Markdown blocks (e.g. a multi-select copy) with a
    /// horizontal rule between them. Empty blocks are skipped.
    public static func list(_ items: [String]) -> String {
        items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n---\n\n")
    }

    /// Formats a checklist line (`- [ ]` / `- [x]`). Convenience for task-like
    /// rows that copy as Markdown checkboxes.
    public static func checklistItem(_ title: String, done: Bool) -> String {
        "- [\(done ? "x" : " ")] \(title.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}
