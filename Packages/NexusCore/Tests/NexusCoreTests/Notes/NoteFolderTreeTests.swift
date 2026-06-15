import Foundation
import Testing

@testable import NexusCore

@Suite("NoteFolderTree")
struct NoteFolderTreeTests {
    @Test("build derives nested nodes with per-path note counts and implied ancestors")
    func buildDerivesTree() {
        let tree = NoteFolderTree.build(paths: [
            "projects/nexus",
            "projects/nexus",
            "projects",
            "archive/2025/q1",  // implies "archive" and "archive/2025" with 0 direct notes
            nil,  // root note — contributes no folder
        ])

        #expect(tree.roots.map(\.path) == ["archive", "projects"])

        let projects = tree.roots[1]
        #expect(projects.name == "projects")
        #expect(projects.depth == 0)
        #expect(projects.noteCount == 1)
        #expect(projects.children.map(\.path) == ["projects/nexus"])
        #expect(projects.children[0].name == "nexus")
        #expect(projects.children[0].depth == 1)
        #expect(projects.children[0].noteCount == 2)

        let archive = tree.roots[0]
        #expect(archive.noteCount == 0)
        #expect(archive.children.map(\.path) == ["archive/2025"])
        #expect(archive.children[0].children.map(\.path) == ["archive/2025/q1"])
        #expect(archive.children[0].children[0].noteCount == 1)
    }

    @Test("flattened is DFS pre-order; allPaths includes implied ancestors")
    func flattenedAndAllPaths() {
        let tree = NoteFolderTree.build(paths: ["b/inner", "a"])

        #expect(tree.flattened.map(\.path) == ["a", "b", "b/inner"])
        #expect(tree.allPaths == ["a", "b", "b/inner"])
        #expect(tree.flattened.map(\.depth) == [0, 0, 1])
    }

    @Test("build normalizes raw paths and sorts siblings case-insensitively")
    func normalizationAndSorting() {
        let tree = NoteFolderTree.build(paths: ["/Zeta//x/", "alpha", "  ", nil])

        #expect(tree.roots.map(\.path) == ["alpha", "Zeta"])
        #expect(tree.roots[1].children.map(\.path) == ["Zeta/x"])
    }

    @Test("empty input yields an empty tree")
    func emptyInput() {
        let tree = NoteFolderTree.build(paths: [nil, "   "])
        #expect(tree.roots.isEmpty)
        #expect(tree.flattened.isEmpty)
    }
}
