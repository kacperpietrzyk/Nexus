import Foundation

// MARK: - Inline content

/// An inline formatting attribute applied to a run of text.
///
/// `link` carries either a `ref` (an object id in the Link graph — a rename-safe
/// wikilink) and/or an `href` (a plain URL). Both may be present; both may be nil
/// for a malformed link that the reconciler will later resolve or drop.
///
/// Codable shape is a discriminated union keyed by `type`. Raw `type` strings land
/// in CloudKit (inside `Note.contentData`) — stable, never rename.
public enum Mark: Codable, Sendable, Equatable {
    case bold
    case italic
    case code
    case strike
    case link(ref: UUID?, href: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case ref
        case href
    }

    private enum Kind: String, Codable {
        case bold
        case italic
        case code
        case strike
        case link
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .bold: self = .bold
        case .italic: self = .italic
        case .code: self = .code
        case .strike: self = .strike
        case .link:
            let ref = try container.decodeIfPresent(UUID.self, forKey: .ref)
            let href = try container.decodeIfPresent(String.self, forKey: .href)
            self = .link(ref: ref, href: href)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bold: try container.encode(Kind.bold, forKey: .type)
        case .italic: try container.encode(Kind.italic, forKey: .type)
        case .code: try container.encode(Kind.code, forKey: .type)
        case .strike: try container.encode(Kind.strike, forKey: .type)
        case .link(let ref, let href):
            try container.encode(Kind.link, forKey: .type)
            try container.encodeIfPresent(ref, forKey: .ref)
            try container.encodeIfPresent(href, forKey: .href)
        }
    }
}

/// A contiguous run of inline text sharing the same set of `marks`.
/// Empty `marks` = plain text.
public struct InlineRun: Codable, Sendable, Equatable {
    public var text: String
    public var marks: [Mark]

    public init(text: String, marks: [Mark] = []) {
        self.text = text
        self.marks = marks
    }
}

// MARK: - Table

/// A single table row: a list of cells, each cell a list of inline runs.
/// Minimal stable shape; richer table semantics (header flag, alignment) are
/// TODO for the serializer step.
public struct TableRow: Codable, Sendable, Equatable {
    public var cells: [[InlineRun]]

    public init(cells: [[InlineRun]]) {
        self.cells = cells
    }
}

// MARK: - Block

/// A structural content block. The canonical content format of a `Note` is an
/// ordered `[Block]`; HTML and Markdown are serializations, not the canon.
///
/// `id` is **stable across decode/encode** — it is the anchor the `NoteReconciler`
/// uses to mirror cross-object refs (`todo` → `TaskItem`, `embed`/`link(ref)` →
/// `Link` rows). Never regenerate a block id on a round-trip.
public struct Block: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var kind: BlockKind

    public init(id: UUID = UUID(), kind: BlockKind) {
        self.id = id
        self.kind = kind
    }
}

/// The variant payload of a `Block`. Discriminated union keyed by `type`; raw
/// `type` strings land in CloudKit (inside `Note.contentData`) — stable, never
/// rename a case.
public enum BlockKind: Codable, Sendable, Equatable {
    case paragraph(runs: [InlineRun])
    case heading(level: Int, runs: [InlineRun])
    /// A live checkbox handle onto a `TaskItem` (the single source of truth for
    /// task fields). `taskRef` is the `TaskItem.id`; `runs` is the cached inline
    /// label.
    case todo(taskRef: UUID, runs: [InlineRun])
    case bulleted(runs: [InlineRun])
    case numbered(runs: [InlineRun])
    case quote(runs: [InlineRun])
    case code(language: String?, text: String)
    case divider
    /// An image. `ref` points at an asset/object id when present; `asset` is a
    /// free-form locator (e.g. a relative path or external URL).
    /// Minimal stable shape — richer asset handling is TODO for later steps.
    case image(ref: UUID?, asset: String?)
    /// A read-only inline transclusion of another object. Mirrored as a
    /// `LinkKind.embed` row by the reconciler.
    case embed(ref: UUID, kind: ItemKind)
    case table(rows: [TableRow])
    /// Escape-hatch raw HTML. Rendered (sanitized) in a WebView; treated as
    /// untrusted when written by the agent/MCP.
    case html(raw: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case runs
        case level
        case taskRef
        case language
        case text
        case ref
        case asset
        case kind
        case rows
        case raw
    }

    private enum Kind: String, Codable {
        case paragraph
        case heading
        case todo
        case bulleted
        case numbered
        case quote
        case code
        case divider
        case image
        case embed
        case table
        case html
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .paragraph:
            self = .paragraph(runs: try container.decode([InlineRun].self, forKey: .runs))
        case .heading:
            self = .heading(
                level: try container.decode(Int.self, forKey: .level),
                runs: try container.decode([InlineRun].self, forKey: .runs)
            )
        case .todo:
            self = .todo(
                taskRef: try container.decode(UUID.self, forKey: .taskRef),
                runs: try container.decode([InlineRun].self, forKey: .runs)
            )
        case .bulleted:
            self = .bulleted(runs: try container.decode([InlineRun].self, forKey: .runs))
        case .numbered:
            self = .numbered(runs: try container.decode([InlineRun].self, forKey: .runs))
        case .quote:
            self = .quote(runs: try container.decode([InlineRun].self, forKey: .runs))
        case .code:
            self = .code(
                language: try container.decodeIfPresent(String.self, forKey: .language),
                text: try container.decode(String.self, forKey: .text)
            )
        case .divider:
            self = .divider
        case .image:
            self = .image(
                ref: try container.decodeIfPresent(UUID.self, forKey: .ref),
                asset: try container.decodeIfPresent(String.self, forKey: .asset)
            )
        case .embed:
            self = .embed(
                ref: try container.decode(UUID.self, forKey: .ref),
                kind: try container.decode(ItemKind.self, forKey: .kind)
            )
        case .table:
            self = .table(rows: try container.decode([TableRow].self, forKey: .rows))
        case .html:
            self = .html(raw: try container.decode(String.self, forKey: .raw))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .paragraph(let runs):
            try container.encode(Kind.paragraph, forKey: .type)
            try container.encode(runs, forKey: .runs)
        case .heading(let level, let runs):
            try container.encode(Kind.heading, forKey: .type)
            try container.encode(level, forKey: .level)
            try container.encode(runs, forKey: .runs)
        case .todo(let taskRef, let runs):
            try container.encode(Kind.todo, forKey: .type)
            try container.encode(taskRef, forKey: .taskRef)
            try container.encode(runs, forKey: .runs)
        case .bulleted(let runs):
            try container.encode(Kind.bulleted, forKey: .type)
            try container.encode(runs, forKey: .runs)
        case .numbered(let runs):
            try container.encode(Kind.numbered, forKey: .type)
            try container.encode(runs, forKey: .runs)
        case .quote(let runs):
            try container.encode(Kind.quote, forKey: .type)
            try container.encode(runs, forKey: .runs)
        case .code(let language, let text):
            try container.encode(Kind.code, forKey: .type)
            try container.encodeIfPresent(language, forKey: .language)
            try container.encode(text, forKey: .text)
        case .divider:
            try container.encode(Kind.divider, forKey: .type)
        case .image(let ref, let asset):
            try container.encode(Kind.image, forKey: .type)
            try container.encodeIfPresent(ref, forKey: .ref)
            try container.encodeIfPresent(asset, forKey: .asset)
        case .embed(let ref, let kind):
            try container.encode(Kind.embed, forKey: .type)
            try container.encode(ref, forKey: .ref)
            try container.encode(kind, forKey: .kind)
        case .table(let rows):
            try container.encode(Kind.table, forKey: .type)
            try container.encode(rows, forKey: .rows)
        case .html(let raw):
            try container.encode(Kind.html, forKey: .type)
            try container.encode(raw, forKey: .raw)
        }
    }
}
