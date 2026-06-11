import Foundation

/// Normalization for `Note.folderPath` (Tranche 2, Obsidian O2). A folder
/// path is a slash-separated, normalized String ("area/subarea"); nil = root.
/// There is NO folder entity — the tree is derived from live notes' paths.
/// Every write path MUST route raw user input through `normalize(_:)`
/// (Plan E's `NoteRepository.setFolderPath`/`renameFolder` enforce this).
public enum NoteFolderPath {
    /// Trims per-component whitespace, collapses duplicate `/`, strips
    /// leading/trailing `/`, DROPS (never resolves) `.`/`..` components;
    /// an empty result → nil (root).
    public static func normalize(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let components =
            raw
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "/")
    }
}
