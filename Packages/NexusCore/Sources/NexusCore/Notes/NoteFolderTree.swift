import Foundation

/// The DERIVED folder tree over notes (Tranche 2 Plan E, spec §4.5). There is NO
/// folder entity (locked decision): a folder is exactly the set of live notes'
/// normalized `folderPath` values, so empty folders cannot exist — except implied
/// ancestors of a deep path, which appear with `noteCount == 0` so move/rename
/// surfaces can target them. Pure value type, `ProjectExecutionModel`-style:
/// built from a snapshot, never touches SwiftData.
public struct NoteFolderTree: Equatable, Sendable {
    /// One folder node. `id == path` (paths are unique by construction).
    public struct Node: Identifiable, Equatable, Sendable {
        /// Last path component, for display.
        public let name: String
        /// Full normalized slash path — the value stored in `Note.folderPath`.
        public let path: String
        /// 0 for root-level folders; +1 per nesting level (indentation hint).
        public let depth: Int
        /// Notes whose `folderPath` equals `path` EXACTLY (not descendants).
        public let noteCount: Int
        public let children: [Node]

        public var id: String { path }

        public init(name: String, path: String, depth: Int, noteCount: Int, children: [Node]) {
            self.name = name
            self.path = path
            self.depth = depth
            self.noteCount = noteCount
            self.children = children
        }
    }

    public let roots: [Node]

    public init(roots: [Node]) {
        self.roots = roots
    }

    /// Build the tree from raw `folderPath` values (nil = root note, contributes
    /// nothing). Inputs are re-normalized defensively (a synced path from another
    /// device build could predate normalization). Siblings sort
    /// case-insensitively for stable, deterministic ordering.
    public static func build(paths: [String?]) -> NoteFolderTree {
        var directCounts: [String: Int] = [:]
        var allFolderPaths = Set<String>()
        for raw in paths {
            guard let path = NoteFolderPath.normalize(raw) else { continue }
            directCounts[path, default: 0] += 1
            var components = path.split(separator: "/").map(String.init)
            while !components.isEmpty {
                allFolderPaths.insert(components.joined(separator: "/"))
                components.removeLast()
            }
        }

        func childPaths(of parent: String?) -> [String] {
            allFolderPaths
                .filter { path in
                    guard let parent else { return !path.contains("/") }
                    guard path.hasPrefix(parent + "/") else { return false }
                    return !path.dropFirst(parent.count + 1).contains("/")
                }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }

        func nodes(under parent: String?, depth: Int) -> [Node] {
            childPaths(of: parent).map { path in
                Node(
                    name: String(path.split(separator: "/").last ?? ""),
                    path: path,
                    depth: depth,
                    noteCount: directCounts[path] ?? 0,
                    children: nodes(under: path, depth: depth + 1)
                )
            }
        }

        return NoteFolderTree(roots: nodes(under: nil, depth: 0))
    }

    /// DFS pre-order flatten — the shape an indented single-column list renders.
    public var flattened: [Node] {
        var result: [Node] = []
        func walk(_ node: Node) {
            result.append(node)
            node.children.forEach(walk)
        }
        roots.forEach(walk)
        return result
    }

    /// Every folder path (including implied ancestors), DFS order — the move-menu
    /// target list.
    public var allPaths: [String] { flattened.map(\.path) }
}
