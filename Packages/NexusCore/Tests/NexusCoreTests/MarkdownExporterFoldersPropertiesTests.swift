import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Tranche 2 Plan E: notes export with `folder:` + flat `prop.<key>` frontmatter
/// extras (decision: flat prefixed keys — the only shape the FROZEN
/// `MarkdownFrontmatterCoder` round-trips for all five `NotePropertyValue` cases)
/// and land in `folderPath` subdirectories with relative-path-keyed dedup.
@MainActor
private func makeNoteContainer() throws -> ModelContainer {
    let schema = Schema([Note.self, Link.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [config])
}

private func makeTempExportFolder() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nexus-export-e-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
@Test func markdownExporter_note_emitsFolderAndPropertyFrontmatter() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)

    let note = Note(title: "Organized")
    note.folderPath = "projects/nexus"
    note.properties = [
        NoteProperty(key: "status", value: .string("active")),
        NoteProperty(key: "priority", value: .number(2)),
        NoteProperty(key: "effort", value: .number(2.5)),
        NoteProperty(key: "pinned", value: .bool(true)),
        NoteProperty(key: "reviewed", value: .date(Date(timeIntervalSince1970: 1_700_000_000))),
        NoteProperty(key: "colors", value: .list(["red", "blue"])),
    ]
    context.insert(note)
    try context.save()

    let folder = try makeTempExportFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)

    let path =
        folder
        .appendingPathComponent("projects/nexus", isDirectory: true)
        .appendingPathComponent("\(note.id.uuidString).md")
    let text = try String(contentsOf: path, encoding: .utf8)

    #expect(text.contains("folder: projects/nexus"))
    #expect(text.contains("prop.status: active"))
    #expect(text.contains("prop.priority: 2"))  // 2.0 collapses to "2"
    #expect(text.contains("prop.effort: 2.5"))
    #expect(text.contains("prop.pinned: true"))
    #expect(text.contains("prop.reviewed: 2023-11-14T22:13:20Z"))
    #expect(text.contains("prop.colors:\n  - red\n  - blue"))

    // Round-trips through the frozen decoder, order preserved, after standard keys.
    let parsed = try MarkdownFrontmatterCoder.decode(text)
    let keys = parsed.fields.map(\.0)
    #expect(
        keys == [
            "id", "kind", "title", "createdAt", "updatedAt", "deletedAt",
            "folder", "prop.status", "prop.priority", "prop.effort",
            "prop.pinned", "prop.reviewed", "prop.colors", "links",
        ])
    let dict = Dictionary(uniqueKeysWithValues: parsed.fields)
    #expect(dict["folder"] == .string("projects/nexus"))
    #expect(dict["prop.status"] == .string("active"))
    #expect(dict["prop.pinned"] == .string("true"))
    #expect(dict["prop.reviewed"] == .date(Date(timeIntervalSince1970: 1_700_000_000)))
    #expect(dict["prop.colors"] == .list([.string("red"), .string("blue")]))
}

@MainActor
@Test func markdownExporter_note_withoutFolderOrPropertiesEmitsNoExtras() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)
    let note = Note(title: "Plain")
    context.insert(note)
    try context.save()

    let folder = try makeTempExportFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)

    let text = try String(
        contentsOf: folder.appendingPathComponent("\(note.id.uuidString).md"),
        encoding: .utf8
    )
    #expect(!text.contains("folder:"))
    #expect(!text.contains("prop."))
}

@MainActor
@Test func markdownExporter_note_sanitizesPropertyKeysForRoundTrip() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)
    let note = Note(title: "Tricky")
    note.properties = [NoteProperty(key: "due: date\nx", value: .string("soon"))]
    context.insert(note)
    try context.save()

    let folder = try makeTempExportFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    _ = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)

    let text = try String(
        contentsOf: folder.appendingPathComponent("\(note.id.uuidString).md"),
        encoding: .utf8
    )
    let parsed = try MarkdownFrontmatterCoder.decode(text)  // must not throw
    #expect(parsed.fields.contains { $0.0 == "prop.due- date x" && $0.1 == .string("soon") })
}

@MainActor
@Test func markdownExporter_note_landsInFolderSubdirectory_nilFolderLandsAtRoot() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)
    let foldered = Note(title: "Deep")
    foldered.folderPath = "area/sub"
    let rootNote = Note(title: "Root")
    context.insert(foldered)
    context.insert(rootNote)
    try context.save()

    let folder = try makeTempExportFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let result = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)

    #expect(result.itemsExported == 2)
    let nested = folder.appendingPathComponent("area/sub/\(foldered.id.uuidString).md")
    let flat = folder.appendingPathComponent("\(rootNote.id.uuidString).md")
    #expect(FileManager.default.fileExists(atPath: nested.path))
    #expect(FileManager.default.fileExists(atPath: flat.path))
}

@MainActor
@Test func markdownExporter_filenameDedupIsKeyedOnRelativePath() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)
    let sharedID = UUID()
    // Same UUID, DIFFERENT folders → both keep the plain <id>.md name.
    let inA = Note(id: sharedID, title: "In A")
    inA.folderPath = "a"
    let inB = Note(id: sharedID, title: "In B")
    inB.folderPath = "b"
    // Same UUID, SAME folder → second gets the disambiguated name.
    let dupID = UUID()
    let first = Note(id: dupID, title: "First")
    first.folderPath = "c"
    let second = Note(id: dupID, title: "Second")
    second.folderPath = "c"
    context.insert(inA)
    context.insert(inB)
    context.insert(first)
    context.insert(second)
    try context.save()

    let folder = try makeTempExportFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let result = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)

    #expect(result.itemsExported == 4)
    let fm = FileManager.default
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("a/\(sharedID.uuidString).md").path))
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("b/\(sharedID.uuidString).md").path))
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("c/\(dupID.uuidString).md").path))
    #expect(fm.fileExists(atPath: folder.appendingPathComponent("c/\(dupID.uuidString)-note.md").path))
}

@MainActor
@Test func markdownExporter_sanitizesHostileFolderComponentsWithoutDroppingTheNote() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)
    let note = Note(title: "Hostile")
    // Bypasses NoteFolderPath.normalize on purpose (e.g. a path synced from a
    // future build): exporter must defend on its own and never drop the note.
    note.folderPath = "a:b/../c"
    context.insert(note)
    try context.save()

    let folder = try makeTempExportFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let result = try await MarkdownExporter.export(container: container, types: Note.self, to: folder)

    #expect(result.itemsExported == 1)
    let expected = folder.appendingPathComponent("a-b/_/c/\(note.id.uuidString).md")
    #expect(FileManager.default.fileExists(atPath: expected.path))
}

@MainActor
@Test func markdownExporter_exportIsByteDeterministicAcrossRuns() async throws {
    let container = try makeNoteContainer()
    let context = ModelContext(container)
    let note = Note(title: "Stable")
    note.folderPath = "projects"
    note.properties = [
        NoteProperty(key: "status", value: .string("active")),
        NoteProperty(key: "pinned", value: .bool(false)),
    ]
    context.insert(note)
    try context.save()

    let folderA = try makeTempExportFolder()
    let folderB = try makeTempExportFolder()
    defer {
        try? FileManager.default.removeItem(at: folderA)
        try? FileManager.default.removeItem(at: folderB)
    }
    _ = try await MarkdownExporter.export(container: container, types: Note.self, to: folderA)
    _ = try await MarkdownExporter.export(container: container, types: Note.self, to: folderB)

    let relative = "projects/\(note.id.uuidString).md"
    let bytesA = try Data(contentsOf: folderA.appendingPathComponent(relative))
    let bytesB = try Data(contentsOf: folderB.appendingPathComponent(relative))
    #expect(bytesA == bytesB)
}
