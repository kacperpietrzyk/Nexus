import Foundation

/// Text-only sidecar that bridges recording-time screen OCR to the post-hoc
/// processing pipeline.
///
/// Recording (in the helper) and processing (in the app pipeline) do not share a
/// process or lifetime — they communicate through files in the per-meeting audio
/// folder (the same pattern as ``RecordingMetadataStore``'s `metadata.json`).
/// Screen OCR therefore cannot hand its text to ``SummaryStage`` in memory; it
/// appends the recognised text to `screen_context.txt` while recording, and the
/// pipeline reads that file back when building the summary/action-item prompts.
///
/// Privacy (spec §7.2 / I4): this file holds ONLY recognised text — never frames.
/// Duplicate snapshots (the same shared window OCR'd twice) are collapsed so the
/// prompt isn't padded with repeated content.
public struct ScreenContextStore: Sendable {
    public init() {}

    /// Append an OCR snapshot to the meeting's screen-context sidecar, skipping a
    /// snapshot identical to the most recent one. Blank text is a no-op.
    public func append(text: String, folder: URL) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }

        var snapshots = (try? read(folder: folder)) ?? []
        guard snapshots.last != trimmed else { return }
        snapshots.append(trimmed)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let joined = snapshots.joined(separator: Self.separator)
        try Data(joined.utf8).write(to: contextURL(folder: folder), options: [.atomic])
    }

    /// All accumulated OCR snapshots in capture order, or `[]` when none were
    /// captured (feature off, or no shared window OCR'd).
    public func read(folder: URL) throws -> [String] {
        let url = contextURL(folder: folder)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard contents.isEmpty == false else { return [] }
        return contents.components(separatedBy: Self.separator)
    }

    /// The joined screen-context text suitable for prompt enrichment, or `nil`
    /// when there is none (so callers can keep the prompt byte-unchanged).
    public func combinedText(folder: URL) -> String? {
        let snapshots = (try? read(folder: folder)) ?? []
        guard snapshots.isEmpty == false else { return nil }
        let joined = snapshots.joined(separator: "\n\n")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func contextURL(folder: URL) -> URL {
        folder.appendingPathComponent("screen_context.txt")
    }

    /// A separator unlikely to appear inside OCR'd UI text, keeping the on-disk
    /// format a plain readable text file while still round-tripping snapshots.
    private static let separator = "\n\u{241E}\n"
}
