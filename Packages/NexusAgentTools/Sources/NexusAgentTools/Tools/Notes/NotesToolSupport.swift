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
        guard let bodyValue = args["body"] else { return nil }
        guard let body = bodyValue.stringValue else {
            throw AgentError.validation("body must be a string")
        }
        let format = try bodyFormat(args["body_format"])
        switch format {
        case .markdown:
            return MarkdownBlockParser.parse(body)
        case .html:
            // No HTML→Blocks parser: wrap verbatim in an html(raw:) block (§4.3/§14).
            return [Block(kind: .html(raw: body))]
        }
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
