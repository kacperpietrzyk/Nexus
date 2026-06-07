import Foundation
import NexusCore
import SwiftUI

/// Converts a `Note`'s inline `[InlineRun]` to a SwiftUI `AttributedString` for
/// display, and back from edited plain text to runs.
///
/// Spec §5 staging: the editor first edits text-bearing blocks as *plain text*
/// (marks preserved only when the whole block carries a single uniform mark set);
/// richer inline-mark editing (selecting a span and toggling bold) is a later
/// stage. Display is always full-fidelity — every mark renders.
public enum InlineRunRendering {

    /// The flat plain text of a run list (no marks) — what the staged plain-text
    /// editor binds to.
    public static func plainText(_ runs: [InlineRun]) -> String {
        runs.map(\.text).joined()
    }

    /// Build a single run carrying `text` with no marks. Used by the staged
    /// plain-text editor: a text edit collapses the block to one unmarked run.
    /// Round-trips losslessly for the common case (a line with no inline marks).
    public static func runs(fromPlainText text: String) -> [InlineRun] {
        text.isEmpty ? [] : [InlineRun(text: text)]
    }

    /// Render runs to an `AttributedString`, applying each run's marks. `link`
    /// marks attach a tappable `noteWikilink` / URL attribute when resolvable.
    public static func attributed(_ runs: [InlineRun]) -> AttributedString {
        var result = AttributedString()
        for run in runs {
            result.append(attributed(run))
        }
        return result
    }

    private static func attributed(_ run: InlineRun) -> AttributedString {
        var piece = AttributedString(run.text)
        var isCode = false
        for mark in run.marks {
            switch mark {
            case .bold:
                piece.inlinePresentationIntent = mergedIntent(piece, .stronglyEmphasized)
            case .italic:
                piece.inlinePresentationIntent = mergedIntent(piece, .emphasized)
            case .strike:
                piece.strikethroughStyle = .single
            case .code:
                isCode = true
            case .link(let ref, let href):
                if let href, let url = URL(string: href) {
                    piece.link = url
                } else if let ref {
                    // Wikilink to a graph object — encoded as a custom URL the
                    // editor intercepts (`nexus://note-ref/<uuid>`). Resolved refs
                    // tint as links; unresolved ones (handled by caller) get a
                    // muted style.
                    piece.link = URL(string: "nexus://note-ref/\(ref.uuidString)")
                }
            }
        }
        if isCode {
            piece.inlinePresentationIntent = mergedIntent(piece, .code)
        }
        return piece
    }

    private static func mergedIntent(
        _ piece: AttributedString,
        _ adding: InlinePresentationIntent
    ) -> InlinePresentationIntent {
        if let existing = piece.inlinePresentationIntent {
            return existing.union(adding)
        }
        return adding
    }

    /// Returns the wikilink target id encoded in a `nexus://note-ref/<uuid>` URL,
    /// or nil if the URL is a plain external link.
    public static func wikilinkTarget(from url: URL) -> UUID? {
        guard url.scheme == "nexus", url.host == "note-ref" else { return nil }
        let raw = url.lastPathComponent
        return UUID(uuidString: raw)
    }
}
