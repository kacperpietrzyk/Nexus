import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
@Test func markdownExporter_export_writesFilePerLinkable() async throws {
    let schema = Schema([DebugItem.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let a = DebugItem(title: "Alpha")
    let b = DebugItem(title: "Beta")
    context.insert(a)
    context.insert(b)
    let link = Link(from: (.debug, a.id), to: (.debug, b.id), linkKind: .mentions)
    context.insert(link)
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try await MarkdownExporter.export(container: container, types: DebugItem.self, to: folder)
    #expect(result.itemsExported == 2)
    #expect(result.linksAttached == 1)

    let aPath = folder.appendingPathComponent("\(a.id.uuidString).md")
    let bPath = folder.appendingPathComponent("\(b.id.uuidString).md")
    #expect(FileManager.default.fileExists(atPath: aPath.path))
    #expect(FileManager.default.fileExists(atPath: bPath.path))

    let aText = try String(contentsOf: aPath, encoding: .utf8)
    #expect(aText.contains("title: Alpha"))
    #expect(aText.contains("toID: \(b.id.uuidString)"))

    let bText = try String(contentsOf: bPath, encoding: .utf8)
    #expect(bText.contains("title: Beta"))
    #expect(bText.contains("links: []"))  // no outgoing links from B
}

@MainActor
@Test func markdownExporter_export_skipsSoftDeleted() async throws {
    let schema = Schema([DebugItem.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let alive = DebugItem(title: "alive")
    let dead = DebugItem(title: "dead")
    dead.deletedAt = .now
    context.insert(alive)
    context.insert(dead)
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try await MarkdownExporter.export(container: container, types: DebugItem.self, to: folder)
    #expect(result.itemsExported == 1)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(alive.id.uuidString).md").path))
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(dead.id.uuidString).md").path))
}

@MainActor
@Test func markdownExporter_export_roundTripsScalars() async throws {
    let schema = Schema([DebugItem.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let item = DebugItem(title: "Round trip")
    context.insert(item)
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    _ = try await MarkdownExporter.export(container: container, types: DebugItem.self, to: folder)
    let text = try String(contentsOf: folder.appendingPathComponent("\(item.id.uuidString).md"), encoding: .utf8)

    let parsed = try MarkdownFrontmatterCoder.decode(text)
    let dict = Dictionary(uniqueKeysWithValues: parsed.fields.map { ($0.0, $0.1) })
    #expect(dict["id"] == .string(item.id.uuidString))
    #expect(dict["kind"] == .string("debug"))
    #expect(dict["title"] == .string("Round trip"))
}

@MainActor
@Test func markdownExporter_export_writesTitle_andOmitsLegacyBody() async throws {
    // Task content moved off `TaskItem.body` into a linked `Note` (spec §4.2).
    // The exporter no longer reads `body`; emitting the linked Note's content as
    // Markdown is the Notes serializer step (see MarkdownExporter.body TODO).
    let schema = Schema([TaskItem.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let task = TaskItem(title: "Exported task", body: "Task body")
    context.insert(task)
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try await MarkdownExporter.export(container: container, types: TaskItem.self, to: folder)
    #expect(result.itemsExported == 1)

    let text = try String(
        contentsOf: folder.appendingPathComponent("\(task.id.uuidString).md"),
        encoding: .utf8
    )
    #expect(text.contains("Exported task"))
    #expect(!text.contains("Task body"))
}

@MainActor
@Test func markdownExporter_export_emitsLinkedNoteContentAsBody() async throws {
    // A task whose `noteRef` points at a `Note` exports that note's canonical
    // `[Block]` content as the Markdown body (the Notes serializer wiring that
    // retires the `MarkdownExporter.body` TODO).
    let schema = Schema([TaskItem.self, Note.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let blocks = [
        Block(kind: .heading(level: 2, runs: [InlineRun(text: "Plan")])),
        Block(kind: .paragraph(runs: [InlineRun(text: "First", marks: [.bold])])),
    ]
    let note = Note(title: "Task note", contentData: try NoteContentCoder.encode(blocks))
    let task = TaskItem(title: "Has a note", noteRef: note.id)
    context.insert(note)
    context.insert(task)
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    _ = try await MarkdownExporter.export(container: container, types: TaskItem.self, to: folder)
    let text = try String(
        contentsOf: folder.appendingPathComponent("\(task.id.uuidString).md"),
        encoding: .utf8
    )
    #expect(text.contains("## Plan"))
    #expect(text.contains("**First**"))
}

@MainActor
@Test func markdownExporter_export_emitsNoteOwnContentAsBody() async throws {
    // A `Note` exported as its own Linkable emits its blocks as the Markdown body.
    let schema = Schema([Note.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    let blocks = [Block(kind: .bulleted(runs: [InlineRun(text: "point")]))]
    let note = Note(title: "Standalone", contentData: try NoteContentCoder.encode(blocks))
    context.insert(note)
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    _ = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)
    let text = try String(
        contentsOf: folder.appendingPathComponent("\(note.id.uuidString).md"),
        encoding: .utf8
    )
    #expect(text.contains("- point"))
}

@MainActor
@Test func markdownExporter_export_writesMultipleTypes() async throws {
    let schema = Schema([TaskItem.self, DebugItem.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)
    context.insert(TaskItem(title: "Task"))
    context.insert(DebugItem(title: "Debug"))
    try context.save()

    let folder = try makeTempFolder()
    defer { try? FileManager.default.removeItem(at: folder) }

    let result = try await MarkdownExporter.export(
        container: container,
        types: TaskItem.self, DebugItem.self,
        to: folder
    )
    #expect(result.itemsExported == 2)
}

private func makeTempFolder() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
