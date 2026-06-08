import Foundation
import SwiftData
import Testing

@testable import NexusCore

/// `PersonRepository` (People/Contacts module, spec §4.1–4.3, §5, §7, §10):
/// CRUD + soft-delete, idempotent dedup upsert, name/alias soft-match, atomic
/// `mergePeople`, the single-user boundary (I1), and graph aggregation via
/// reverse-query. Tests build their own in-memory schema (`[Person, Link]`) — no
/// NexusSchema/NexusSync dependency, no cross-package model resolution.
@Suite("PersonRepository")
struct PersonRepositoryTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Person.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        ModelContext(try makeContainer())
    }

    // MARK: - CRUD + soft-delete (§10)

    @MainActor
    @Test("create then find round-trips")
    func createAndFind() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice", company: "Acme")
        let found = try repo.find(id: person.id)
        #expect(found?.displayName == "Alice")
        #expect(found?.company == "Acme")
    }

    @MainActor
    @Test("update mutates fields and bumps updatedAt")
    func update() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context, now: { Date(timeIntervalSince1970: 1000) })
        let person = try repo.create(displayName: "Alice")
        try repo.update(person, displayName: "Alice B", email: "a@example.com")
        #expect(person.displayName == "Alice B")
        #expect(person.email == "a@example.com")
    }

    @MainActor
    @Test("softDelete tombstones and excludes from allActive")
    func softDelete() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice")
        try repo.softDelete(person)
        #expect(person.deletedAt != nil)
        #expect(try repo.allActive().isEmpty)
    }

    @MainActor
    @Test("softDelete removes incident edges but leaves the meeting/task intact (I4)")
    func softDeleteRemovesEdges() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice")
        let meetingID = UUID()
        try repo.linkAttendee(meetingID: meetingID, personID: person.id)
        try repo.softDelete(person)
        let links = LinkRepository(context: context)
        #expect(try links.backlinks(to: (.person, person.id)).isEmpty)
        // The meeting endpoint simply no longer has the edge; the meeting row is
        // owned by another module and is untouched here.
        #expect(try links.outgoing(from: (.meeting, meetingID)).isEmpty)
    }

    // MARK: - Dedup upsert (§4.3, §10)

    @MainActor
    @Test("same externalSourceID updates rather than duplicating")
    func upsertIdempotent() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let key = "calendar-attendee:alice@example.com"
        let first = try repo.upsert(externalSourceID: key, displayName: "Alice")
        let second = try repo.upsert(externalSourceID: key, displayName: "Alice Smith", company: "Acme")
        #expect(first.id == second.id)
        #expect(try repo.allActive().count == 1)
        #expect(second.displayName == "Alice Smith")
        #expect(second.company == "Acme")
    }

    @MainActor
    @Test("upsert unions aliases and never clobbers with blanks")
    func upsertEnriches() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let key = "src:1"
        _ = try repo.upsert(externalSourceID: key, displayName: "Alice", aliases: ["A"], email: "a@x.com")
        let updated = try repo.upsert(externalSourceID: key, displayName: "Alice", aliases: ["Speaker_1"], email: nil)
        #expect(Set(updated.aliases) == Set(["A", "Speaker_1"]))
        #expect(updated.email == "a@x.com")  // not clobbered by nil
    }

    @MainActor
    @Test("upsert keeps a real displayName instead of clobbering it with an email placeholder (ME1)")
    func upsertDoesNotClobberRealNameWithEmail() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let key = "calendar-attendee:bob@x.com"
        let named = try repo.upsert(externalSourceID: key, displayName: "Bob Smith", email: "bob@x.com")
        // A later email-only attendee re-upserts with displayName == email (a placeholder).
        let reupserted = try repo.upsert(externalSourceID: key, displayName: "bob@x.com", email: "bob@x.com")
        #expect(reupserted.id == named.id)
        #expect(reupserted.displayName == "Bob Smith")  // real name preserved
    }

    @MainActor
    @Test("upsert still upgrades an email-placeholder displayName to a real name (ME1)")
    func upsertUpgradesPlaceholderToRealName() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let key = "calendar-attendee:bob@x.com"
        // First seen email-only: displayName is the email placeholder.
        _ = try repo.upsert(externalSourceID: key, displayName: "bob@x.com", email: "bob@x.com")
        // A later attendee carries the real name — it must win over the placeholder.
        let upgraded = try repo.upsert(externalSourceID: key, displayName: "Bob Smith", email: "bob@x.com")
        #expect(upgraded.displayName == "Bob Smith")
    }

    @MainActor
    @Test("upsert with a new externalSourceID creates a distinct person")
    func upsertCreatesNew() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        _ = try repo.upsert(externalSourceID: "src:1", displayName: "Alice")
        _ = try repo.upsert(externalSourceID: "src:2", displayName: "Bob")
        #expect(try repo.allActive().count == 2)
    }

    // MARK: - Soft-match (§4.3, §10)

    @MainActor
    @Test("suggestExisting matches by name case/diacritic-insensitively")
    func softMatchName() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        _ = try repo.create(displayName: "Renée Müller")
        let hit = try repo.suggestExisting(matching: "renee muller")
        #expect(hit?.displayName == "Renée Müller")
    }

    @MainActor
    @Test("suggestExisting matches by alias")
    func softMatchAlias() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let alice = try repo.create(displayName: "Alice", aliases: ["Speaker_1"])
        let hit = try repo.suggestExisting(matching: "SPEAKER_1")
        #expect(hit?.id == alice.id)
    }

    @MainActor
    @Test("suggestExisting returns nil on no match and ignores tombstones")
    func softMatchMiss() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let bob = try repo.create(displayName: "Bob")
        #expect(try repo.suggestExisting(matching: "Nobody") == nil)
        try repo.softDelete(bob)
        #expect(try repo.suggestExisting(matching: "Bob") == nil)
    }

    // MARK: - mergePeople (§4.3, I2, §10)

    @MainActor
    @Test("merge repoints edges, merges fields, soft-deletes the duplicate")
    func mergeRepoints() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let into = try repo.create(displayName: "Alice", email: "alice@x.com")
        let from = try repo.create(displayName: "A. Smith", company: "Acme", externalSourceID: "src:dup")

        let meetingID = UUID()
        let taskID = UUID()
        try repo.linkAttendee(meetingID: meetingID, personID: from.id)
        try repo.linkMention(source: .task, sourceID: taskID, personID: from.id)

        try repo.mergePeople(into: into, from: from)

        // Duplicate soft-deleted.
        #expect(from.deletedAt != nil)
        #expect(try repo.allActive().count == 1)

        // Aliases merged (display name + aliases of the source folded in).
        #expect(into.aliases.contains("A. Smith"))

        // Empty into-fields filled from source.
        #expect(into.company == "Acme")
        #expect(into.email == "alice@x.com")  // pre-existing not overwritten

        // Edges repointed onto into; none left on from (no orphan — I2).
        let links = LinkRepository(context: context)
        #expect(try links.backlinks(to: (.person, from.id)).isEmpty)
        let intoBacklinks = try links.backlinks(to: (.person, into.id))
        #expect(intoBacklinks.count == 2)
        #expect(intoBacklinks.allSatisfy { $0.toID == into.id })
    }

    @MainActor
    @Test("merge de-duplicates an edge that both people share")
    func mergeDeDupesSharedEdge() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let into = try repo.create(displayName: "Alice")
        let from = try repo.create(displayName: "Alice2")
        let meetingID = UUID()
        try repo.linkAttendee(meetingID: meetingID, personID: into.id)
        try repo.linkAttendee(meetingID: meetingID, personID: from.id)

        try repo.mergePeople(into: into, from: from)

        let links = LinkRepository(context: context)
        let backlinks = try links.backlinks(to: (.person, into.id))
        #expect(backlinks.count == 1)  // not duplicated
        #expect(try links.backlinks(to: (.person, from.id)).isEmpty)
    }

    @MainActor
    @Test("merge into self throws and saves nothing")
    func mergeSelfThrows() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice")
        #expect(throws: PersonMergeError.cannotMergeIntoSelf(personID: person.id)) {
            try repo.mergePeople(into: person, from: person)
        }
        #expect(person.deletedAt == nil)
    }

    @MainActor
    @Test("merge precondition: an already-deleted source throws before any mutation")
    func mergeRejectsDeletedSource() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context, now: { Date(timeIntervalSince1970: 5) })
        let into = try repo.create(displayName: "Alice")
        let from = try repo.create(displayName: "Dup")
        try repo.linkAttendee(meetingID: UUID(), personID: from.id)
        try repo.softDelete(from)  // source already gone

        // This guard fires on the function's first lines, BEFORE any repoint/field
        // mutation, so nothing is touched. (This is a precondition test — true
        // mid-failure atomicity is structural; see handoff notes.)
        #expect(throws: PersonMergeError.sourceAlreadyDeleted(personID: from.id)) {
            try repo.mergePeople(into: into, from: from)
        }
        #expect(into.aliases.isEmpty)
    }

    @MainActor
    @Test("merge durably repoints with no orphan edges (I2 — verified on a fresh context)")
    func mergeNoOrphanAfterCommit() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = PersonRepository(context: context)
        let into = try repo.create(displayName: "Alice")
        let from = try repo.create(displayName: "Dup")
        try repo.linkAttendee(meetingID: UUID(), personID: from.id)
        try repo.linkMention(source: .note, sourceID: UUID(), personID: from.id)

        try repo.mergePeople(into: into, from: from)

        // Read on a FRESH context over the same container: the single terminal save
        // committed the full repoint — every edge now points at `into`, none dangle
        // on `from` (no orphan, I2).
        let fresh = ModelContext(container)
        let links = LinkRepository(context: fresh)
        #expect(try links.backlinks(to: (.person, from.id)).isEmpty)
        #expect(try links.backlinks(to: (.person, into.id)).count == 2)
    }

    // MARK: - Single-user boundary I1 (§5, §10)

    @MainActor
    @Test("task ↔ person link is always .mentions, never an assignee edge (I1)")
    func boundaryTaskMentionsOnly() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice")
        let taskID = UUID()
        let edge = try repo.linkMention(source: .task, sourceID: taskID, personID: person.id)
        #expect(edge.linkKind == .mentions)
        #expect(edge.fromKind == .task)
        #expect(edge.toKind == .person)
    }

    @MainActor
    @Test("note ↔ person link is .mentions; meeting ↔ person is .attendee")
    func boundaryEdgeLabels() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice")
        let noteEdge = try repo.linkMention(source: .note, sourceID: UUID(), personID: person.id)
        let attendeeEdge = try repo.linkAttendee(meetingID: UUID(), personID: person.id)
        #expect(noteEdge.linkKind == .mentions)
        #expect(attendeeEdge.linkKind == .attendee)
    }

    // MARK: - Aggregation (§7, §10)

    @MainActor
    @Test("aggregate returns meetings (.attendee) + tasks/notes (.mentions) via reverse-query")
    func aggregateGroupsByKind() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Alice")
        let meetingID = UUID()
        let taskID = UUID()
        let noteID = UUID()
        try repo.linkAttendee(meetingID: meetingID, personID: person.id)
        try repo.linkMention(source: .task, sourceID: taskID, personID: person.id)
        try repo.linkMention(source: .note, sourceID: noteID, personID: person.id)

        let aggregate = try repo.aggregate(person)
        #expect(aggregate.meetings == [meetingID])
        #expect(aggregate.tasks == [taskID])
        #expect(aggregate.notes == [noteID])
    }

    @MainActor
    @Test("aggregate is empty for an unlinked person")
    func aggregateEmpty() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)
        let person = try repo.create(displayName: "Loner")
        #expect(try repo.aggregate(person) == PersonAggregate())
    }
}
