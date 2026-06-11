import Foundation

/// One custom note property (Tranche 2, Obsidian O6). Stored as part of an
/// ordered `[NoteProperty]` array (NOT a dict — preserves user order so
/// frontmatter emission stays deterministic) JSON-encoded into
/// `Note.propertiesJSON`. Keys are unique case-sensitively within a note (the
/// editor enforces; `Note.properties` de-duplicates last-wins defensively).
public struct NoteProperty: Codable, Equatable, Sendable {
    public var key: String
    public var value: NotePropertyValue

    public init(key: String, value: NotePropertyValue) {
        self.key = key
        self.value = value
    }
}

/// A property value. Codable, CloudKit-agnostic (lives only inside the JSON
/// blob, never as a column). The persisted encoding (synthesized Codable) is
/// pinned by test — never change it without a data migration for existing
/// blobs. Export mapping to `FrontmatterValue` is Plan E (spec §2.4: `.string`
/// → `.string`, `.date` → `.date`, `.list` → `.list`, `.number`/`.bool` →
/// `.string` — the frozen coder gains no new cases this tranche).
public enum NotePropertyValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    case list([String])
}
