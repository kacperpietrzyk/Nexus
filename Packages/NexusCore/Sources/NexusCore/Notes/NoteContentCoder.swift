import Foundation

/// Encodes/decodes the canonical `[Block]` content of a `Note` to/from the
/// `Note.contentData` blob.
///
/// The wire shape is the `Block` Codable form (discriminated union keyed by
/// `type`; pinned by `BlockTests`). This is a thin, deterministic JSON codec so
/// both the serializers and `MarkdownExporter` share one definition of "how a
/// note's content is stored" instead of each spelling out `JSONEncoder`/
/// `JSONDecoder`. The encoder uses sorted keys for a stable on-disk byte shape.
public enum NoteContentCoder {
    /// Decode an empty/absent blob as an empty document rather than throwing, so
    /// a freshly-created `Note` (default `contentData == Data()`) reads as zero
    /// blocks on the hot path.
    public static func decode(_ data: Data) throws -> [Block] {
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([Block].self, from: data)
    }

    public static func encode(_ blocks: [Block]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(blocks)
    }
}
