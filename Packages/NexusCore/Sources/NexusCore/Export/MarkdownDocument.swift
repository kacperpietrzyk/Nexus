import Foundation

/// Plain value type representing one rendered `.md` file. Constructed by `MarkdownExporter`
/// from a concrete `Linkable` plus its outgoing `Link` rows.
public struct MarkdownDocument: Sendable {
    public struct LinkRef: Sendable, Equatable {
        public let toKind: ItemKind
        public let toID: UUID
        public let linkKind: LinkKind
        public init(toKind: ItemKind, toID: UUID, linkKind: LinkKind) {
            self.toKind = toKind
            self.toID = toID
            self.linkKind = linkKind
        }
    }

    public let id: UUID
    public let kind: ItemKind
    public let title: String
    public let createdAt: Date
    public let updatedAt: Date
    public let deletedAt: Date?
    /// Extra frontmatter fields emitted after `deletedAt` and before `links`
    /// (e.g. a meeting's `startedAt`/`attendees` — see `MarkdownExportRenderable`).
    /// Caller-supplied order is preserved — same determinism contract as the
    /// base fields.
    public let extraFrontmatter: [(String, FrontmatterValue)]
    public let outgoingLinks: [LinkRef]
    public let body: String

    public init(
        id: UUID,
        kind: ItemKind,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        deletedAt: Date?,
        extraFrontmatter: [(String, FrontmatterValue)] = [],
        outgoingLinks: [LinkRef],
        body: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.extraFrontmatter = extraFrontmatter
        self.outgoingLinks = outgoingLinks
        self.body = body
    }

    public var filename: String { "\(id.uuidString).md" }

    public func render() -> String {
        var fields: [(String, FrontmatterValue)] = [
            ("id", .string(id.uuidString)),
            ("kind", .string(kind.rawValue)),
            ("title", .string(title)),
            ("createdAt", .date(createdAt)),
            ("updatedAt", .date(updatedAt)),
            ("deletedAt", deletedAt.map { .date($0) } ?? .none),
        ]
        fields.append(contentsOf: extraFrontmatter)
        let sortedLinks = outgoingLinks.sorted {
            ($0.toKind.rawValue, $0.toID.uuidString, $0.linkKind.rawValue)
                < ($1.toKind.rawValue, $1.toID.uuidString, $1.linkKind.rawValue)
        }
        if sortedLinks.isEmpty {
            fields.append(("links", .list([])))
        } else {
            let listItems: [FrontmatterValue] = sortedLinks.map { link in
                .dict([
                    ("toKind", .string(link.toKind.rawValue)),
                    ("toID", .string(link.toID.uuidString)),
                    ("linkKind", .string(link.linkKind.rawValue)),
                ])
            }
            fields.append(("links", .list(listItems)))
        }
        let frontmatter = MarkdownFrontmatterCoder.encode(fields: fields)
        let header = "# \(title)\n\n"
        let bodyText = body.isEmpty ? "" : "\(body)\n"
        return frontmatter + "\n" + header + bodyText
    }
}
