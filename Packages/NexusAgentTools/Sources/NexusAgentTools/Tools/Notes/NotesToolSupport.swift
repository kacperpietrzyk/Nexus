import Foundation
import NexusCore

/// Shared argument parsing + body→blocks handling for the `note.*` MCP tools.
///
/// ## Body formats (spec §11/§12)
/// A note's content is written as either `markdown` (the real round-trip path,
/// parsed by `MarkdownBlockParser`) or `html`. There is no HTML→Blocks parser; an
/// `html` body is wrapped verbatim in a single `html(raw:)` block — the escape-hatch
/// the model already defines (§4.3) and renders sanitized (§14). This keeps untrusted
/// agent HTML quarantined in one block instead of being mis-parsed as markdown.
enum NotesToolSupport {
    struct ParsedBody {
        let blocks: [Block]
        let frontmatter: FrontmatterMetadata?
    }

    struct FrontmatterMetadata {
        let title: String?
        let role: NoteRole?
        let tags: [String]?
        let links: [MarkdownDocument.LinkRef]
    }

    /// The supported write formats for a note body. Distinct from `NoteContentFormat`
    /// (which also has `plain`, a read-only projection that cannot round-trip back to
    /// blocks).
    enum BodyFormat: String, CaseIterable {
        case markdown
        case html
    }

    /// Parse the optional `(body, body_format)` pair into blocks. Returns `nil` when
    /// `body` is omitted (so callers can distinguish "leave content untouched" from
    /// "set empty content").
    static func blocks(fromBodyIn args: JSONValue) throws -> [Block]? {
        try parsedBody(fromBodyIn: args)?.blocks
    }

    /// Parse the optional `(body, body_format)` pair into blocks plus import
    /// metadata, when the markdown body is a full anti-lock-in document.
    static func parsedBody(fromBodyIn args: JSONValue) throws -> ParsedBody? {
        guard let bodyValue = args["body"] else { return nil }
        guard let body = bodyValue.stringValue else {
            throw AgentError.validation("body must be a string")
        }
        let format = try bodyFormat(args["body_format"])
        switch format {
        case .markdown:
            let markdown = markdownDocument(body)
            return ParsedBody(
                blocks: MarkdownBlockParser.parse(markdown.body),
                frontmatter: markdown.frontmatter
            )
        case .html:
            // No HTML→Blocks parser: wrap verbatim in an html(raw:) block (§4.3/§14).
            return ParsedBody(blocks: [Block(kind: .html(raw: body))], frontmatter: nil)
        }
    }

    /// Accept either a raw note body or a full anti-lock-in export document. The
    /// core parser is intentionally body-only; MCP is the import/write boundary.
    private static func markdownDocument(_ markdown: String) -> (body: String, frontmatter: FrontmatterMetadata?) {
        guard markdown.hasPrefix("---\n"),
            let parsed = try? MarkdownFrontmatterCoder.decode(markdown)
        else {
            return (markdown, nil)
        }
        return (parsed.body, metadata(from: parsed.fields))
    }

    private static func metadata(from fields: [(String, FrontmatterValue)]) -> FrontmatterMetadata {
        let title = stringField("title", in: fields)
        let role = stringField("role", in: fields).flatMap(NoteRole.init(rawValue:))
        let tags = listField("tags", in: fields)
        let links = linkRefsField("links", in: fields)
        return FrontmatterMetadata(title: title, role: role, tags: tags, links: links)
    }

    private static func stringField(_ name: String, in fields: [(String, FrontmatterValue)]) -> String? {
        guard case .string(let value)? = fields.first(where: { $0.0 == name })?.1 else {
            return nil
        }
        return value
    }

    private static func listField(_ name: String, in fields: [(String, FrontmatterValue)]) -> [String]? {
        guard case .list(let values)? = fields.first(where: { $0.0 == name })?.1 else {
            return nil
        }
        return values.compactMap { value in
            guard case .string(let text) = value else { return nil }
            return text
        }
    }

    private static func linkRefsField(_ name: String, in fields: [(String, FrontmatterValue)]) -> [MarkdownDocument.LinkRef] {
        guard case .list(let values)? = fields.first(where: { $0.0 == name })?.1 else {
            return []
        }
        return values.compactMap { value in
            guard case .dict(let pairs) = value else { return nil }
            return linkRef(from: pairs)
        }
    }

    private static func linkRef(from pairs: [(String, FrontmatterValue)]) -> MarkdownDocument.LinkRef? {
        guard
            let toKindText = stringField("toKind", in: pairs),
            let toKind = ItemKind(rawValue: toKindText),
            let toIDText = stringField("toID", in: pairs),
            let toID = UUID(uuidString: toIDText),
            let linkKindText = stringField("linkKind", in: pairs),
            let linkKind = LinkKind(rawValue: linkKindText)
        else {
            return nil
        }
        return MarkdownDocument.LinkRef(toKind: toKind, toID: toID, linkKind: linkKind)
    }

    /// Default body format is markdown (the round-trip path). `body_format` is
    /// validated against `BodyFormat`.
    static func bodyFormat(_ value: JSONValue?) throws -> BodyFormat {
        guard let value else { return .markdown }
        guard let text = value.stringValue else {
            throw AgentError.validation("body_format must be a string")
        }
        guard let format = BodyFormat(rawValue: text) else {
            throw AgentError.validation(
                "body_format must be one of: \(BodyFormat.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return format
    }

    /// Parse the optional `format` field for read tools into a `NoteContentFormat`.
    /// Defaults to `markdown`.
    static func readFormat(_ value: JSONValue?) throws -> NoteContentFormat {
        guard let value else { return .markdown }
        guard let text = value.stringValue else {
            throw AgentError.validation("format must be a string")
        }
        guard let format = NoteContentFormat(rawValue: text) else {
            throw AgentError.validation(
                "format must be one of: \(NoteContentFormat.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return format
    }

    static func role(_ value: JSONValue?) throws -> NoteRole? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("role must be a string")
        }
        guard let role = NoteRole(rawValue: text) else {
            throw AgentError.validation(
                "role must be one of: \(NoteRole.allCases.map(\.rawValue).joined(separator: ", "))"
            )
        }
        return role
    }

    static func tags(_ value: JSONValue?) throws -> [String]? {
        guard let value else { return nil }
        guard let values = value.arrayValue else {
            throw AgentError.validation("tags must be an array of strings")
        }
        return try values.enumerated().map { index, element in
            guard let tag = element.stringValue else {
                throw AgentError.validation("tags[\(index)] must be a string")
            }
            return tag
        }
    }

    static func optionalString(_ value: JSONValue?, field: String) throws -> String? {
        guard let value else { return nil }
        guard let text = value.stringValue else {
            throw AgentError.validation("\(field) must be a string")
        }
        return text
    }

    static func requiredUUID(_ value: JSONValue?, field: String) throws -> UUID {
        guard let text = value?.stringValue else {
            throw AgentError.validation("Missing required string field: \(field)")
        }
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a valid UUID")
        }
        return id
    }

    /// Reusable JSON Schema fragment for the body + body_format pair.
    static var bodyProperties: [String: JSONSchema] {
        [
            "body": .string(
                description: "Note content. Markdown by default (round-trips to blocks); pass body_format=html to store raw HTML verbatim."
            ),
            "body_format": .string(
                enumValues: BodyFormat.allCases.map(\.rawValue),
                description: "How `body` is interpreted: markdown (default) | html."
            ),
        ]
    }
}
