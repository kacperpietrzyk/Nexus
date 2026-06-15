import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Test-only stand-in for a feature-module Linkable (like NexusMeetings'
/// `Meeting`) that owns its export rendering. Declared here (not a retroactive
/// conformance on `DebugItem`) so the conformance is owned by this module.
@Model
final class ExportRenderableFixture: Linkable, MarkdownExportRenderable {
    var id: UUID = UUID()
    var kind: ItemKind = ItemKind.debug
    var title: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var deletedAt: Date?

    init(title: String) {
        self.title = title
    }

    func exportFrontmatterExtras() -> [(String, FrontmatterValue)] {
        [("custom", .string("extra-value"))]
    }

    func exportMarkdownBody(in context: ModelContext) -> String {
        "## Custom body\n\nRendered by the conformance."
    }
}

@MainActor
@Test func markdownExporter_export_usesRenderableConformance() async throws {
    let schema = Schema([ExportRenderableFixture.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let item = ExportRenderableFixture(title: "Custom")
    context.insert(item)
    try context.save()

    let folder = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-renderable-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try await MarkdownExporter.export(
        container: container,
        types: ExportRenderableFixture.self,
        to: folder
    )
    #expect(result.itemsExported == 1)

    let text = try String(
        contentsOf: folder.appendingPathComponent("\(item.id.uuidString).md"),
        encoding: .utf8
    )
    #expect(text.contains("custom: extra-value"))
    #expect(text.contains("## Custom body"))
    // Extras land in the frontmatter (before `links`), not in the body.
    let customRange = try #require(text.range(of: "custom: extra-value"))
    let linksRange = try #require(text.range(of: "links:"))
    #expect(customRange.lowerBound < linksRange.lowerBound)
}
