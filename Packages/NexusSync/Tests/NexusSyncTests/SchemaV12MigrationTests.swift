import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

/// V11 -> V12 migration: additive registration of the `Person` contact-record
/// entity (People / Contacts module, spec §4.1/§8), plus the optional, idempotent
/// `participantsJSON` -> `Person` backfill.
///
/// The whole V11 -> V12 delta is lightweight-additive: a shipped-V11 on-disk store
/// physically lacks the `Person` table; the V12 build's lightweight inference adds
/// it in one pass. There is no data move. The new `ItemKind.person` /
/// `LinkKind.attendee` raw enum cases are stored as existing `String` columns on the
/// `Link` table and need no schema change.
///
/// The backfill runs as plain code (NOT a migration stage) and — unlike the V11
/// system-label seed — is NOT wired into `NexusModelContainer.make`: it needs the
/// concrete `Meeting` type (a composition-time extra NexusSync cannot import), so its
/// invocation is deferred to first-launch bootstrap. These tests exercise it over a
/// `StubMeeting` stand-in (the sanctioned NexusSync-can't-see-Meeting workaround).
@Suite struct SchemaV12MigrationTests {
    // MARK: - Schema shape

    @Test func v12AddsPersonToV11Models() {
        #expect(NexusSchemaV12.models.count == NexusSchemaV11.models.count + 1)
        #expect(NexusSchemaV12.models.contains { $0 == Person.self })
    }

    @Test func v12VersionIsHigherThanV11() {
        #expect(NexusSchemaV12.versionIdentifier > NexusSchemaV11.versionIdentifier)
    }

    @Test func migrationPlanIncludesV12Schema() {
        #expect(NexusMigrationPlan.schemas.contains { $0 == NexusSchemaV12.self })
    }

    /// `Person` is a SYNCED partition (spec §4.1): contact records mirror to the
    /// CloudKit private DB so they travel with the user's meetings/tasks across
    /// devices. It must NOT slip into `localOnlyBaseline`. The on-disk crown-jewel
    /// test runs with CloudKit off (both partitions local), so it cannot tell the two
    /// apart — this is the one discriminating check that pins the requirement.
    @Test func personIsASyncedPartitionNotLocalOnly() {
        let partitions = NexusModelContainer.modelPartitions(extraModels: [StubSyncedExtra.self])
        #expect(partitions.syncedModels.contains { String(describing: $0) == "Person" })
        #expect(!partitions.localOnlyModels.contains { String(describing: $0) == "Person" })
    }

    /// The V11 -> V12 stage is lightweight-additive (Person table). It MUST stay
    /// `.lightweight`: the production split container drops the plan and relies on
    /// inference, so a `.custom` stage here would never run for real users.
    @Test func v11ToV12StageIsLightweight() {
        let v11ToV12 = NexusMigrationPlan.stages
            .map { String(describing: $0) }
            .filter { $0.contains("V11") && $0.contains("V12") }
        #expect(v11ToV12.count == 1)
        #expect(v11ToV12.allSatisfy { $0.contains("lightweight") })
    }

    // MARK: - Fresh V12 store (persist / fetch)

    /// A fresh V12 store accepts `Person` inserts and round-trips its fields,
    /// including `kind == .person` and the `Searchable` text. Proves the additive
    /// entity persists and fetches.
    @Test func freshV12StoreAllowsPersonInsertAndRoundTrips() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV12.models, version: NexusSchemaV12.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let person = Person(
            displayName: "Alice Smith",
            aliases: ["Alice"],
            email: "alice@example.com",
            company: "Acme",
            externalSourceID: "calendar-attendee:alice@example.com"
        )
        context.insert(person)
        try context.save()

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        let fetched = try #require(people.first)
        #expect(fetched.kind == .person)
        #expect(fetched.displayName == "Alice Smith")
        #expect(fetched.aliases == ["Alice"])
        #expect(fetched.email == "alice@example.com")
        #expect(fetched.searchableText == "Alice Smith Alice Acme")
    }

    /// Soft-delete works on `Person` (consistent with the other models): a deleted
    /// person carries `deletedAt` and remains physically present.
    @Test func personSoftDeleteSetsDeletedAt() throws {
        let container = try ModelContainer(
            for: Schema(NexusSchemaV12.models, version: NexusSchemaV12.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let person = Person(displayName: "Bob")
        #expect(person.deletedAt == nil)
        context.insert(person)
        try context.save()

        person.deletedAt = Date(timeIntervalSince1970: 1_790_100_000)
        try context.save()

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        #expect(people.first?.deletedAt == Date(timeIntervalSince1970: 1_790_100_000))
    }

    // MARK: - Backfill (participantsJSON -> Person + .attendee)

    /// Backfill creates one `Person` per unique participant `displayName` and a
    /// `.attendee` edge from each meeting to each of its participants. A name shared
    /// across two meetings yields exactly ONE `Person` (global dedup) with TWO edges.
    @Test func backfillCreatesPeopleAndAttendeeEdges() throws {
        let context = try makeBackfillContext()

        let meeting1 = StubMeeting(participants: [("s1", "Alice"), ("s2", "Bob")])
        let meeting2 = StubMeeting(participants: [("s1", "Alice"), ("s3", "Carol")])
        context.insert(meeting1)
        context.insert(meeting2)
        try context.save()

        try runBackfill(in: context)

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(Set(people.map(\.displayName)) == ["Alice", "Bob", "Carol"])
        #expect(people.count == 3)  // Alice deduplicated across two meetings.

        let attendeeEdges = try attendeeLinks(in: context)
        #expect(attendeeEdges.count == 4)  // m1->Alice, m1->Bob, m2->Alice, m2->Carol.

        // Every edge is .meeting -> .person via .attendee (never an assignee/owner).
        #expect(attendeeEdges.allSatisfy { $0.fromKind == .meeting && $0.toKind == .person })

        // Alice's single Person is the attendee endpoint of both her meetings.
        let alice = try #require(people.first { $0.displayName == "Alice" })
        let aliceMeetingIDs = Set(attendeeEdges.filter { $0.toID == alice.id }.map(\.fromID))
        #expect(aliceMeetingIDs == [meeting1.id, meeting2.id])
    }

    /// Backfill is idempotent: running it twice yields the SAME `Person` set and the
    /// SAME `.attendee` edges (no duplicate people, no double-linking). Spec §8/§10.
    @Test func backfillIsIdempotentAcrossTwoRuns() throws {
        let context = try makeBackfillContext()
        context.insert(StubMeeting(participants: [("s1", "Alice"), ("s2", "Bob")]))
        context.insert(StubMeeting(participants: [("s1", "Alice")]))
        try context.save()

        try runBackfill(in: context)
        let peopleAfterFirst = Set(try context.fetch(FetchDescriptor<Person>()).map(\.id))
        let edgesAfterFirst = try attendeeLinks(in: context).count

        try runBackfill(in: context)
        let peopleAfterSecond = Set(try context.fetch(FetchDescriptor<Person>()).map(\.id))
        let edgesAfterSecond = try attendeeLinks(in: context).count

        #expect(peopleAfterSecond == peopleAfterFirst)
        #expect(peopleAfterSecond.count == 2)  // Alice + Bob.
        #expect(edgesAfterSecond == edgesAfterFirst)
        #expect(edgesAfterSecond == 3)  // m1->Alice, m1->Bob, m2->Alice.
    }

    /// Empty / nil `participantsJSON` contributes NO people and NO links (spec §8).
    @Test func backfillWithEmptyParticipantsCreatesNoPeople() throws {
        let context = try makeBackfillContext()
        context.insert(StubMeeting(participants: []))  // nil participantsJSON
        let emptyData = StubMeeting(participants: [])
        emptyData.participantsJSON = Data()  // empty (not nil) JSON
        context.insert(emptyData)
        try context.save()

        try runBackfill(in: context)

        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        #expect(try attendeeLinks(in: context).isEmpty)
    }

    /// A store with zero meetings is a clean no-op (no people, no links).
    @Test func backfillWithNoMeetingsIsNoOp() throws {
        let context = try makeBackfillContext()

        try runBackfill(in: context)

        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        #expect(try attendeeLinks(in: context).isEmpty)
    }

    /// Backfill does not create a duplicate when a `Person` with the same
    /// `displayName` already exists (e.g. previously added manually): it reuses the
    /// existing record and links the meeting to it.
    @Test func backfillReusesExistingPersonByDisplayName() throws {
        let context = try makeBackfillContext()
        let preexisting = Person(displayName: "Alice", email: "alice@manual.example")
        context.insert(preexisting)
        context.insert(StubMeeting(participants: [("s1", "Alice")]))
        try context.save()

        try runBackfill(in: context)

        let alices = try context.fetch(
            FetchDescriptor<Person>(predicate: #Predicate { $0.displayName == "Alice" })
        )
        #expect(alices.count == 1)
        #expect(alices.first?.id == preexisting.id)  // reused, not re-created.
        #expect(alices.first?.email == "alice@manual.example")  // existing fields untouched.

        let edges = try attendeeLinks(in: context)
        #expect(edges.count == 1)
        #expect(edges.first?.toID == preexisting.id)
    }

    /// M2: a pre-existing `Person` stored with surrounding whitespace must still
    /// be matched by the trimmed participant name — no duplicate on backfill.
    @Test func backfillTrimsExistingPersonNameForDedup() throws {
        let context = try makeBackfillContext()
        let preexisting = Person(displayName: " Alice ")  // stored untrimmed
        context.insert(preexisting)
        context.insert(StubMeeting(participants: [("s1", "Alice")]))
        try context.save()

        try runBackfill(in: context)

        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)  // no duplicate despite the whitespace mismatch.
        #expect(people.first?.id == preexisting.id)  // reused, not re-created.
        #expect(try attendeeLinks(in: context).count == 1)
    }

    // MARK: - `...IfNeeded` wrapper (marker-gated invocation, M1)

    /// The wrapper runs the backfill once and the per-store marker short-circuits
    /// later launches — even if new meetings appear afterwards (idempotency is
    /// guaranteed by the core; the marker just avoids the rescan).
    @Test func ifNeededWrapperRunsOnceThenMarkerSkips() throws {
        let container = try makeBackfillContainer()
        let context = ModelContext(container)
        context.insert(StubMeeting(participants: [("s1", "Alice"), ("s2", "Bob")]))
        try context.save()
        let defaults = isolatedDefaults()

        try NexusModelContainer.backfillPeopleFromMeetingsIfNeeded(
            meetingType: StubMeeting.self,
            participantsKeyPath: \.participantsJSON,
            idKeyPath: \.id,
            container: container,
            defaults: defaults
        )
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 2)

        // A meeting added after the first run is NOT backfilled — the marker gates.
        context.insert(StubMeeting(participants: [("s3", "Carol")]))
        try context.save()
        try NexusModelContainer.backfillPeopleFromMeetingsIfNeeded(
            meetingType: StubMeeting.self,
            participantsKeyPath: \.participantsJSON,
            idKeyPath: \.id,
            container: container,
            defaults: defaults
        )
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 2)  // Carol not added.
    }

    /// A zero-meeting first launch must NOT set the marker (fresh-install upgrade
    /// where CloudKit hasn't synced historical meetings down yet) — a later launch
    /// once meetings have arrived still backfills them. Guards the M1 failure class.
    @Test func ifNeededWrapperDoesNotMarkEmptyFirstRunAndBackfillsLater() throws {
        let container = try makeBackfillContainer()
        let context = ModelContext(container)
        let defaults = isolatedDefaults()

        // First launch: no meetings synced yet → no-op, marker left UNSET.
        try NexusModelContainer.backfillPeopleFromMeetingsIfNeeded(
            meetingType: StubMeeting.self,
            participantsKeyPath: \.participantsJSON,
            idKeyPath: \.id,
            container: container,
            defaults: defaults
        )
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)

        // Meetings sync down; a later launch backfills them (marker wasn't gating).
        context.insert(StubMeeting(participants: [("s1", "Alice")]))
        try context.save()
        try NexusModelContainer.backfillPeopleFromMeetingsIfNeeded(
            meetingType: StubMeeting.self,
            participantsKeyPath: \.participantsJSON,
            idKeyPath: \.id,
            container: container,
            defaults: defaults
        )
        #expect(try context.fetch(FetchDescriptor<Person>()).count == 1)
    }

    // MARK: - Production split-container path (on-disk, crown jewel)

    /// THE deliverable. Seeds a real on-disk store stamped at V11 holding a
    /// `TaskItem`, a `Project`, and a composition-time synced extra
    /// (`StubSyncedExtra`, the Meeting stand-in), then reopens through the REAL
    /// production entry `NexusModelContainer.make` (the split synced + local-only
    /// container that DROPS the migration plan and relies on lightweight inference).
    /// Proves the V11 -> V12 delta is additive with NO data loss:
    ///   1. the `Person` table is inferred and a `Person` is insertable on the
    ///      migrated store,
    ///   2. the pre-V12 `TaskItem` / `Project` survived intact,
    ///   3. the Meeting stand-in row SURVIVED (no destructive migration),
    ///   4. the V11 system labels are still present (no regression of the prior tier).
    @MainActor
    @Test func splitContainerInfersV11ToV12AdditiveExpansionOnDisk() throws {
        let storeURL = temporaryV12StoreURL(prefix: "nexus-v11-to-v12-additive")
        defer { cleanupV12Stores(at: storeURL) }
        defer { clearV12Markers(for: storeURL) }

        let taskID = UUID()
        let projectID = UUID()
        try seedV11SyncedStore(at: storeURL, taskID: taskID, projectID: projectID)

        // Reopen through the REAL production entry. `make()` emits the split
        // synced + local-only container (dropping the plan → lightweight inference
        // adds the Person table).
        let container = try NexusModelContainer.make(
            environment: V12MigrationTestEnvironment(),
            fileURL: storeURL,
            extraModels: [StubSyncedExtra.self]
        )
        let context = ModelContext(container)

        // (1) Person table inferred + insertable on the migrated store.
        #expect(try context.fetch(FetchDescriptor<Person>()).isEmpty)
        let person = Person(displayName: "Dana", externalSourceID: "calendar-attendee:dana@example.com")
        context.insert(person)
        try context.save()
        let people = try context.fetch(FetchDescriptor<Person>())
        #expect(people.count == 1)
        #expect(people.first?.kind == .person)

        // (2) Pre-V12 TaskItem / Project survived intact.
        let task = try #require(try context.fetch(FetchDescriptor<TaskItem>()).first { $0.id == taskID })
        #expect(task.title == "Pre-V12 task")
        let project = try #require(try context.fetch(FetchDescriptor<Project>()).first { $0.id == projectID })
        #expect(project.name == "Pre-V12 project")

        // (3) Meeting stand-in survived (no destructive migration).
        let survivors = try context.fetch(FetchDescriptor<StubSyncedExtra>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.label == "keep me across V12")

        // (4) V11 system labels still present (prior tier not regressed).
        let labels = try context.fetch(FetchDescriptor<Label>())
        #expect(labels.count == SystemLabel.allCases.count)
    }

    // MARK: - Helpers

    private func makeBackfillContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(
                NexusSchemaV12.assembledModels(extraModels: [StubMeeting.self]),
                version: NexusSchemaV12.versionIdentifier
            ),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeBackfillContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(
                NexusSchemaV12.assembledModels(extraModels: [StubMeeting.self]),
                version: NexusSchemaV12.versionIdentifier
            ),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A throwaway defaults suite so the per-store marker never leaks across tests
    /// (in-memory containers can share a synthetic store URL).
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "people-backfill-\(UUID().uuidString)")!
    }

    private func runBackfill(in context: ModelContext) throws {
        try NexusMigrationPlan.backfillPeopleFromMeetingParticipants(
            meetingType: StubMeeting.self,
            participantsKeyPath: \.participantsJSON,
            idKeyPath: \.id,
            in: context
        )
    }

    private func attendeeLinks(in context: ModelContext) throws -> [Link] {
        try context.fetch(FetchDescriptor<Link>()).filter { $0.linkKind == .attendee }
    }
}

// MARK: - On-disk fixtures

private struct V12MigrationTestEnvironment: NexusEnvironmentProviding {
    let cloudKitEnabled = false
    let cloudKitContainerIdentifier = "iCloud.com.kacperpietrzyk.Nexus"
}

/// Seeds a synced (main) store stamped at V11 with one `TaskItem`, one `Project`,
/// and a composition-time synced extra entity. Mirrors what the split container
/// physically writes to the main store URL before V12 lands.
@MainActor
private func seedV11SyncedStore(at url: URL, taskID: UUID, projectID: UUID) throws {
    let schema = NexusSchemaV11.schema(extraModels: [StubSyncedExtra.self])
    let container = try ModelContainer(
        for: schema,
        migrationPlan: NexusMigrationPlan.self,
        configurations: [
            ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        ]
    )
    let context = ModelContext(container)

    let task = TaskItem(title: "Pre-V12 task")
    task.id = taskID
    context.insert(task)

    let project = Project(name: "Pre-V12 project")
    project.id = projectID
    context.insert(project)

    context.insert(StubSyncedExtra(label: "keep me across V12"))
    try context.save()
}

private func temporaryV12StoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupV12Stores(at storeURL: URL) {
    let urls = [storeURL, NexusModelContainer.localOnlyStoreURL(for: storeURL)]
    for url in urls {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
    }
}

/// Clears the per-store post-open markers so a reused tmpdir path never carries a
/// marker into another run (both the body -> Note conversion and the system-label
/// seed are exercised by `make()` even on a fresh path).
private func clearV12Markers(for storeURL: URL) {
    UserDefaults.standard.removeObject(
        forKey: NexusModelContainer.taskBodyToNoteMigrationCompletionKey(for: storeURL)
    )
    UserDefaults.standard.removeObject(
        forKey: NexusModelContainer.systemLabelSeedCompletionKey(for: storeURL)
    )
}

/// Stand-in for `Meeting` (NexusSync cannot import NexusMeetings). Carries the two
/// fields the backfill reads via key paths: `participantsJSON` and `id`. The JSON
/// is encoded with the same `{speakerID, displayName}` shape the real
/// `MeetingParticipant` persists, so the backfill's minimal `displayName`-only decode
/// is exercised against the real on-disk format (extra `speakerID` key ignored).
@Model
final class StubMeeting {
    var id: UUID
    var participantsJSON: Data?

    init(id: UUID = UUID(), participants: [(speakerID: String, displayName: String)]) {
        self.id = id
        if participants.isEmpty {
            self.participantsJSON = nil
        } else {
            let entries = participants.map { StubParticipant(speakerID: $0.speakerID, displayName: $0.displayName) }
            self.participantsJSON = try? JSONEncoder().encode(entries)
        }
    }
}

/// Mirrors the real persisted `MeetingParticipant` JSON shape for the stub.
private struct StubParticipant: Codable {
    let speakerID: String
    let displayName: String
}
