import Foundation
import NexusCore

/// A serialisable snapshot of a `Note` for MCP tool responses.
///
/// The `body` is rendered into the requested serialization format (markdown / html /
/// plain) by the tool; `NoteDTO` itself just carries metadata + the already-rendered
/// body. The canonical `[Block]` blob is never exposed over MCP — agents read/write
/// markdown or html, the app keeps blocks as the source of truth.
public struct NoteDTO: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let role: String
    public let tags: [String]
    /// Rendered content in the requested `format` (markdown / html / plain).
    public let body: String
    /// Echoes the serialization format used for `body`.
    public let format: String
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, role, tags, body, format
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        title: String,
        role: String,
        tags: [String],
        body: String,
        format: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.tags = tags
        self.body = body
        self.format = format
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Build a DTO from a live `Note`, rendering its content into `format`.
    @MainActor
    public init(from note: Note, format: NoteContentFormat) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.id = note.id.uuidString
        self.title = note.title
        self.role = note.role.rawValue
        self.tags = note.tags
        self.body = try NoteContentFormatRenderer.render(note, as: format)
        self.format = format.rawValue
        self.createdAt = formatter.string(from: note.createdAt)
        self.updatedAt = formatter.string(from: note.updatedAt)
    }
}

/// Serialization format for a note's content over MCP. The canonical storage is
/// always `[Block]`; these are the read/write projections (spec §11/§12).
public enum NoteContentFormat: String, Codable, Sendable, CaseIterable {
    case markdown
    case html
    case plain
}

/// Renders a `Note`'s canonical block content into a requested text format.
///
/// `plain` returns the denormalized `plainText` cache directly (no block decode on
/// the hot path); `markdown`/`html` decode the blob and run the matching serializer.
public enum NoteContentFormatRenderer {
    @MainActor
    public static func render(_ note: Note, as format: NoteContentFormat) throws -> String {
        switch format {
        case .plain:
            return note.plainText
        case .markdown:
            return BlockMarkdownSerializer.markdown(for: try NoteContentCoder.decode(note.contentData))
        case .html:
            return BlockHTMLSerializer.html(for: try NoteContentCoder.decode(note.contentData))
        }
    }
}
