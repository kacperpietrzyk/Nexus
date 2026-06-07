import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// V8 -> V9 migration: the crown-jewel data-safety step (spec §15). V9 adds the
/// `Note` content layer plus additive `TaskItem.noteRef` / `Project.canonicalNoteRef`,
/// and a one-time custom stage that converts each non-empty legacy `TaskItem.body`
/// into a `Note` so existing user content is preserved (never silently dropped).
@Suite struct SchemaV9MigrationTests {
    // MARK: - Schema shape

    @Test func v9AddsNoteToV8Models() {
        #expect(NexusSchemaV9.models.count == NexusSchemaV8.models.count + 1)
        #expect(NexusSchemaV9.models.contains { $0 == Note.self })
    }

    @Test func v9VersionIsHigherThanV8() {
        #expect(NexusSchemaV9.versionIdentifier > NexusSchemaV8.versionIdentifier)
    }

    @Test func migrationPlanIncludesV9Schema() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV9.self })
    }

    /// The V8 -> V9 SCHEMA delta is lightweight-additive (Note table + two `UUID?`
    /// ref fields). The `TaskItem.body` -> `Note` data move is deliberately NOT a
    /// migration stage (see `NexusMigrationPlan` / `migrateTaskBodiesToNotesIfNeeded`):
    /// it runs as plain code over the already-open container because the production
    /// split container drops the plan, and a plan-driven staged migration throws on
    /// any store carrying composition extras (Meeting). Proven end-to-end by
    /// `splitContainerMigratesTaskBodiesToNotesOnDisk`.
    @Test func v8ToV9StageIsLightweight() {
        let v8ToV9 = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { $0.contains("V8") && $0.contains("V9") }
        #expect(v8ToV9.count == 1)
        #expect(v8ToV9.allSatisfy { $0.contains("lightweight") })
    }

    // MARK: - Fresh V9 store

    @Test func freshV9StoreAllowsNoteInserts() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(NexusSchemaV9.models, version: NexusSchemaV9.versionIdentifier),
            configurations: config
        )
        let context = ModelContext(container)
        let note = Note(title: "Fresh", plainText: "hello", role: .free)
        context.insert(note)
        context.insert(TaskItem(title: "with ref", noteRef: note.id))
        try context.save()

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes.first?.title == "Fresh")
        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        #expect(tasks.first?.noteRef == note.id)
    }

    // MARK: - Custom stage (single-config staged-plan path)

    /// Directly exercises the `didMigrate` conversion on an in-memory V9 context:
    /// non-empty `body` becomes a `Note` with the parsed content + flattened
    /// `plainText`; empty `body` gets none; the `noteRef` is wired.
    @Test func didMigrateConvertsNonEmptyBodiesToNotes() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV9.models, version: NexusSchemaV9.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let withBody = TaskItem(title: "Has content")
        withBody.body = "# Heading\n\nA paragraph."
        let empty = TaskItem(title: "No content")
        empty.body = ""
        let whitespaceOnly = TaskItem(title: "Whitespace")
        whitespaceOnly.body = "   \n  "
        context.insert(withBody)
        context.insert(empty)
        context.insert(whitespaceOnly)
        try context.save()

        try NexusMigrationPlan.migrateTaskBodiesToNotes(in: context)

        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.role == .free)
        #expect(note.title == "Has content")
        #expect(note.plainText == "Heading\nA paragraph.")
        let decoded = try NoteContentCoder.decode(note.contentData)
        #expect(decoded.count == 2)

        let refreshedWithBody = try #require(
            try context.fetch(FetchDescriptor<TaskItem>())
                .first { $0.id == withBody.id }
        )
        #expect(refreshedWithBody.noteRef == note.id)
        let refreshedEmpty = try #require(
            try context.fetch(FetchDescriptor<TaskItem>())
                .first { $0.id == empty.id }
        )
        #expect(refreshedEmpty.noteRef == nil)
        let refreshedWhitespace = try #require(
            try context.fetch(FetchDescriptor<TaskItem>())
                .first { $0.id == whitespaceOnly.id }
        )
        #expect(refreshedWhitespace.noteRef == nil)
    }

    /// Idempotency (spec §17): a second `didMigrate` run creates no new `Note` and
    /// preserves the existing `noteRef` (tasks already carrying a ref are skipped).
    @Test func didMigrateIsIdempotent() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV9.models, version: NexusSchemaV9.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let task = TaskItem(title: "Twice")
        task.body = "stable content"
        context.insert(task)
        try context.save()

        try NexusMigrationPlan.migrateTaskBodiesToNotes(in: context)
        let firstNotes = try context.fetch(FetchDescriptor<Note>())
        #expect(firstNotes.count == 1)
        let firstRef = try #require(
            try context.fetch(FetchDescriptor<TaskItem>()).first?.noteRef
        )

        try NexusMigrationPlan.migrateTaskBodiesToNotes(in: context)
        let secondNotes = try context.fetch(FetchDescriptor<Note>())
        #expect(secondNotes.count == 1)
        let secondRef = try #require(
            try context.fetch(FetchDescriptor<TaskItem>()).first?.noteRef
        )
        #expect(firstRef == secondRef)
    }

    // MARK: - Production split-container path (on-disk, crown jewel)

    /// THE deliverable. Seeds a real on-disk store stamped at V8 holding a
    /// `TaskItem` with a non-empty `body`, an empty-`body` `TaskItem`, and a
    /// composition-time synced extra (`StubSyncedExtra`, the Meeting stand-in),
    /// then reopens through the REAL production entry `NexusModelContainer.make`
    /// (the split synced + local-only container that DROPS the migration plan and
    /// relies on the one-time pre-pass). Proves:
    ///   1. the non-empty body became a `Note` with the right `noteRef` +
    ///      `plainText`,
    ///   2. the empty-body task got NO `Note`,
    ///   3. the Meeting stand-in row SURVIVED (no destructive migration — the
    ///      second, orthogonal data-loss landmine),
    ///   4. no pre-existing rows were lost.
    @MainActor
    @Test func splitContainerMigratesTaskBodiesToNotesOnDisk() throws {
        let storeURL = temporaryV9StoreURL(prefix: "nexus-v8-to-v9-body-migration")
        defer { cleanupV9Stores(at: storeURL) }
        // The conversion marker is keyed by store path; this fresh temp path is
        // never marked, so `make()` runs the conversion on first open. Clear it on
        // exit so a reused tmpdir path never carries the marker into another run.
        defer {
            UserDefaults.standard.removeObject(
                forKey: NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
            )
        }

        let withBodyID = UUID()
        let emptyBodyID = UUID()
        try seedV8SyncedStore(
            at: storeURL,
            withBodyID: withBodyID,
            emptyBodyID: emptyBodyID
        )

        // Reopen through the REAL production entry. `make()` emits the split
        // synced + local-only container (dropping the plan → lightweight
        // inference adds the Note table), then runs the body -> Note conversion
        // post-open on that same container.
        let container = try NexusModelContainer.make(
            environment: V9MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        let context = ModelContext(container)

        // (1) Non-empty body converted.
        let notes = try context.fetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.role == .free)
        #expect(note.plainText == "Body that must survive")

        let tasks = try context.fetch(FetchDescriptor<TaskItem>())
        let withBody = try #require(tasks.first { $0.id == withBodyID })
        #expect(withBody.noteRef == note.id)

        // (2) Empty body → no Note.
        let emptyBody = try #require(tasks.first { $0.id == emptyBodyID })
        #expect(emptyBody.noteRef == nil)

        // (4) No data lost.
        #expect(tasks.count == 2)

        // (3) Meeting stand-in survived (no destructive migration).
        let survivors = try context.fetch(FetchDescriptor<StubSyncedExtra>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.label == "keep me across V9")
    }

    /// The marker short-circuits a second conversion: after completion, a freshly
    /// appended legacy body is NOT converted (the container's tasks are never
    /// re-scanned for body migration).
    @MainActor
    @Test func taskBodyMigrationRunsOnlyOncePerStore() throws {
        let storeURL = temporaryV9StoreURL(prefix: "nexus-v9-migration-once")
        defer { cleanupV9Stores(at: storeURL) }

        let suiteName = "nexus-v9-migration-once-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstID = UUID()
        try seedV8SyncedStore(at: storeURL, withBodyID: firstID, emptyBodyID: UUID())

        // First pass: open the split container (inference adds the Note table) and
        // run the conversion with the injected marker store.
        let container = try NexusModelContainer.make(
            environment: V9MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        try NexusModelContainer.migrateTaskBodiesToNotesIfNeeded(
            container: container,
            storeURL: storeURL,
            defaults: defaults
        )
        let key = NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
        #expect(defaults.bool(forKey: key))
        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).count == 1)

        // Append a fresh task with a body and NO noteRef so only the marker (not
        // the conversion's own idempotency) can short-circuit the second pass.
        let appendContext = ModelContext(container)
        let appended = TaskItem(title: "Appended after completion")
        appended.body = "appended body should NOT be converted"
        appended.noteRef = nil
        appendContext.insert(appended)
        try appendContext.save()

        // Second pass is marker-gated → the appended body is NOT converted.
        try NexusModelContainer.migrateTaskBodiesToNotesIfNeeded(
            container: container,
            storeURL: storeURL,
            defaults: defaults
        )
        #expect(
            try ModelContext(container).fetch(FetchDescriptor<Note>()).count == 1,
            "marker must prevent a second conversion pass"
        )
    }

    /// Fresh install (empty store): the post-open conversion is a harmless no-op
    /// that creates no `Note` and DOES set the marker (zero tasks → nothing to
    /// scan ever again for this store).
    @MainActor
    @Test func freshInstallIsAHarmlessNoOp() throws {
        let storeURL = temporaryV9StoreURL(prefix: "nexus-v9-migration-fresh")
        defer { cleanupV9Stores(at: storeURL) }

        let suiteName = "nexus-v9-migration-fresh-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try NexusModelContainer.make(
            environment: V9MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        try NexusModelContainer.migrateTaskBodiesToNotesIfNeeded(
            container: container,
            storeURL: storeURL,
            defaults: defaults
        )

        #expect(try ModelContext(container).fetch(FetchDescriptor<Note>()).isEmpty)
        let key = NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
        #expect(defaults.bool(forKey: key))
    }
}

// MARK: - Fixtures

private struct V9MigrationTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

/// Seeds a synced (main) store stamped at V8 with two tasks (one with a non-empty
/// `body`, one empty) and a composition-time synced extra entity. Mirrors what the
/// split container physically writes to the main store URL before V9 lands.
@MainActor
private func seedV8SyncedStore(at url: URL, withBodyID: UUID, emptyBodyID: UUID) throws {
    let schema = NexusSchemaV8.schema(extraModels: [StubSyncedExtra.self])
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)

    let withBody = TaskItem(title: "Has body")
    withBody.id = withBodyID
    withBody.body = "Body that must survive"
    context.insert(withBody)

    let emptyBody = TaskItem(title: "No body")
    emptyBody.id = emptyBodyID
    emptyBody.body = ""
    context.insert(emptyBody)

    context.insert(StubSyncedExtra(label: "keep me across V9"))
    try context.save()
}

private func temporaryV9StoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupV9Stores(at storeURL: URL) {
    let urls = [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}
