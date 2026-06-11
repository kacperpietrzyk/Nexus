import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("MarkdownExporter + Cycle")
struct MarkdownExporterCycleTests {
    @MainActor
    @Test("a live cycle exports one markdown file; soft-deleted cycles are skipped")
    func cycleExports() async throws {
        let schema = Schema([Cycle.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let live = Cycle(name: "Sprint 12", startAt: stamp, endAt: stamp.addingTimeInterval(14 * 86_400))
        let dead = Cycle(name: "Gone", startAt: stamp, endAt: stamp.addingTimeInterval(86_400))
        dead.deletedAt = stamp
        context.insert(live)
        context.insert(dead)
        try context.save()

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("cycle-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }

        let result = try await MarkdownExporter.export(container: container, types: Cycle.self, to: folder)

        #expect(result.itemsExported == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.filter { $0.hasSuffix(".md") }.count == 1)
    }
}
