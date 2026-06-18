import Foundation
import NexusCore
import NexusUI

/// Pure helpers for note→Markdown and note copy-link formatting.
///
/// Used by both the iOS and macOS list surfaces (and testable in isolation).
public enum NoteMarkdownExport {

    /// Formats a note as Markdown using the canonical `MarkdownExport.entity`
    /// shape: `# Title`, a metadata bullet list (folder + tags), then the plain
    /// text body.
    public static func markdown(for note: Note) -> String {
        var meta: [String] = []
        if let folder = note.folderPath {
            meta.append("Folder: \(folder)")
        }
        let tags = NoteListGrouping.normalizedTags(note.tags)
        if !tags.isEmpty {
            meta.append("Tags: \(tags.joined(separator: ", "))")
        }
        let displayTitle = note.title.isEmpty ? "Untitled" : note.title
        return MarkdownExport.entity(
            title: displayTitle,
            body: note.plainText,
            metadata: meta
        )
    }

    /// Returns the wikilink string for this note: `[[title]]`.
    /// This is the canonical in-app inline-link syntax used by the `[[`
    /// autocomplete path.  "Copy link" pastes this into any plain-text field.
    public static func wikilink(for note: Note) -> String {
        let title = note.title.isEmpty ? "Untitled" : note.title
        return "[[\(title)]]"
    }
}
