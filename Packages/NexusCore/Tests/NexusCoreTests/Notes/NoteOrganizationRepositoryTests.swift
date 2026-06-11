import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// Tranche 2 Plan E: `NoteRepository` write paths for the custom property bag
/// (`Note.propertiesJSON`) and folder placement (`Note.folderPath`). Views and
/// agent tools never write the blob/path directly — these are the single seams.
@MainActor
struct NoteOrganizationRepositoryTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    // MARK: - updateProperties

    @Test func updatePropertiesPersistsOrderedBagAndBumpsUpdatedAt() throws {
        let context = try makeContext()
        var stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = NoteRepository(context: context, now: { stamp })
        let note = try repo.create(title: "Doc")
        stamp = Date(timeIntervalSince1970: 1_700_000_100)

        try repo.updateProperties(
            note,
            properties: [
                NoteProperty(key: "status", value: .string("active")),
                NoteProperty(key: "priority", value: .number(2)),
            ]
        )

        #expect(note.properties.map(\.key) == ["status", "priority"])
        #expect(note.properties[1].value == .number(2))
        #expect(note.propertiesJSON != nil)
        #expect(note.updatedAt == stamp)
    }

    @Test func updatePropertiesDeduplicatesKeysLastValueWinsAtFirstPosition() throws {
        let context = try makeContext()
        let repo = NoteRepository(context: context)
        let note = try repo.create(title: "Doc")

        try repo.updateProperties(
            note,
            properties: [
                NoteProperty(key: "status", value: .string("draft")),
                NoteProperty(key: "owner", value: .string("kacper")),
                NoteProperty(key: "status", value: .string("active")),
            ]
        )

        #expect(
            note.properties == [
                NoteProperty(key: "status", value: .string("active")),
                NoteProperty(key: "owner", value: .string("kacper")),
            ]
        )
    }

    @Test func updatePropertiesEmptyArrayClearsBag() throws {
        let context = try makeContext()
        let repo = NoteRepository(context: context)
        let note = try repo.create(title: "Doc")
        try repo.updateProperties(note, properties: [NoteProperty(key: "k", value: .bool(true))])

        try repo.updateProperties(note, properties: [])

        #expect(note.properties.isEmpty)
    }

    // MARK: - setFolderPath

    @Test func setFolderPathNormalizesAndBumpsUpdatedAt() throws {
        let context = try makeContext()
        var stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = NoteRepository(context: context, now: { stamp })
        let note = try repo.create(title: "Doc")
        stamp = Date(timeIntervalSince1970: 1_700_000_100)

        try repo.setFolderPath(note, "/projects//nexus/")

        #expect(note.folderPath == "projects/nexus")
        #expect(note.updatedAt == stamp)
    }

    @Test func setFolderPathNilOrEmptyMovesToRoot() throws {
        let context = try makeContext()
        let repo = NoteRepository(context: context)
        let note = try repo.create(title: "Doc")
        try repo.setFolderPath(note, "area")

        try repo.setFolderPath(note, nil)
        #expect(note.folderPath == nil)

        try repo.setFolderPath(note, "area")
        try repo.setFolderPath(note, "   ")
        #expect(note.folderPath == nil)
    }

    @Test func setFolderPathUnchangedIsNoOp() throws {
        let context = try makeContext()
        var stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let repo = NoteRepository(context: context, now: { stamp })
        let note = try repo.create(title: "Doc")
        try repo.setFolderPath(note, "area/sub")
        let before = note.updatedAt
        stamp = Date(timeIntervalSince1970: 1_700_000_999)

        try repo.setFolderPath(note, "area//sub")  // normalizes to the same path

        #expect(note.updatedAt == before)
    }
}
