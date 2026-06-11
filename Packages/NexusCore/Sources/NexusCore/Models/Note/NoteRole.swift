import Foundation

/// Role discriminator for a `Note`. Distinguishes a free-standing knowledge-base
/// note from a Project's canonical page or an Agent-fed daily note.
///
/// Stored directly on `Note.role` and lands in CloudKit — stable raw values,
/// never rename a case after introduction (pinned by test).
public enum NoteRole: String, Codable, Sendable, CaseIterable {
    /// Default: a standalone note that lives on its own (knowledge base).
    case free
    /// The canonical page of a `Project` (`Project.canonicalNoteRef`).
    case projectPage
    /// A per-day note, typically populated by the Agent brief.
    case dailyNote
    /// A reusable note template (Tranche 2, Obsidian O3). Instantiation copies
    /// content into a fresh `.free` note (Plan D).
    case template
}
