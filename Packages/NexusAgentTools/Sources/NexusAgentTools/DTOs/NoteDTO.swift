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
    /// Normalized folder path; nil = root (Tranche 2 Plan E).
    public let folder: String?
    /// Ordered custom property bag. Values are JSON-typed; dates serialize as
    /// ISO8601 strings (`.withInternetDateTime`).
    public let properties: [NotePropertyDTO]
    /// Rendered content in the requested `format` (markdown / html / plain).
    public let body: String
    /// Echoes the serialization format used for `body`.
    public let format: String
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, title, role, tags, folder, properties, body, format
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        title: String,
        role: String,
        tags: [String],
        folder: String? = nil,
        properties: [NotePropertyDTO] = [],
        body: String,
        format: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.title = title
        self.role = role
        self.tags = tags
        self.folder = folder
        self.properties = properties
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
        self.folder = note.folderPath
        self.properties = note.properties.map(NotePropertyDTO.init(from:))
        self.body = try NoteContentFormatRenderer.render(note, as: format)
        self.format = format.rawValue
        self.createdAt = formatter.string(from: note.createdAt)
        self.updatedAt = formatter.string(from: note.updatedAt)
    }
}

/// One custom note property over MCP: key + JSON-typed value.
public struct NotePropertyDTO: Codable, Sendable, Equatable {
    public let key: String
    public let value: JSONValue

    public init(key: String, value: JSONValue) {
        self.key = key
        self.value = value
    }

    public init(from property: NoteProperty) {
        self.key = property.key
        switch property.value {
        case .string(let text): self.value = .string(text)
        case .number(let number):
            // Integral doubles collapse to .int so the wire shape is stable
            // across a JSON round-trip (2.0 encodes as `2`, which decodes as
            // .int) — the same Int(exactly:) collapse the exporter uses.
            self.value = Int(exactly: number).map { .int($0) } ?? .double(number)
        case .bool(let flag): self.value = .bool(flag)
        case .date(let date): self.value = .string(Self.isoFormatter.string(from: date))
        case .list(let items): self.value = .array(items.map { .string($0) })
        }
    }

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
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
            return BlockMarkdownSerializer.markdown(
                for: try NoteContentCoder.decode(note.contentData),
                options: .mcpRoundTrip
            )
        case .html:
            return BlockHTMLSerializer.html(for: try NoteContentCoder.decode(note.contentData))
        }
    }
}
