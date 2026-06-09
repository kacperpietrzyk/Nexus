import Foundation
import NexusCore
import SwiftData
import Testing

@testable import PeopleFeature

/// End-to-end "everything about X" resolution (spec §1/§6/§7): the marquee feature.
/// Exercises the real `PersonRepository.aggregate` reverse-query plus the SwiftData
/// fetches that turn its raw endpoints into concrete `TaskItem`/`Note` rows, against
/// a live in-memory `ModelContext`. This is the discriminator that catches a
/// `#Predicate` that compiles but fails to translate at runtime — the silent
/// empty-profile failure mode.
@Suite("PersonAggregateResolver")
struct PersonAggregateResolverTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Person.self, TaskItem.self, Note.self, Link.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("Mentioning tasks resolve from the aggregate's task endpoints")
    func resolvesMentioningTasks() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)

        let person = try repo.create(displayName: "Alice")
        let task = TaskItem(title: "Follow up with Alice")
        context.insert(task)
        try context.save()
        try repo.linkMention(source: .task, sourceID: task.id, personID: person.id)

        let aggregate = try repo.aggregate(person)
        #expect(aggregate.tasks == [task.id])

        let resolved = try PersonAggregateResolver.resolveTasks(ids: aggregate.tasks, in: context)
        #expect(resolved.map(\.id) == [task.id])
        #expect(resolved.first?.title == "Follow up with Alice")
    }

    @MainActor
    @Test("Mentioning notes resolve from the aggregate's note endpoints")
    func resolvesMentioningNotes() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)

        let person = try repo.create(displayName: "Bob")
        let note = Note(title: "1:1 with Bob")
        context.insert(note)
        try context.save()
        try repo.linkMention(source: .note, sourceID: note.id, personID: person.id)

        let aggregate = try repo.aggregate(person)
        let resolved = try PersonAggregateResolver.resolveNotes(ids: aggregate.notes, in: context)
        #expect(resolved.map(\.id) == [note.id])
    }

    @MainActor
    @Test("Soft-deleted mentioning rows are excluded")
    func excludesSoftDeleted() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)

        let person = try repo.create(displayName: "Carol")
        let live = TaskItem(title: "Live task")
        let dead = TaskItem(title: "Tombstoned task")
        dead.deletedAt = .now
        context.insert(live)
        context.insert(dead)
        try context.save()
        try repo.linkMention(source: .task, sourceID: live.id, personID: person.id)
        try repo.linkMention(source: .task, sourceID: dead.id, personID: person.id)

        let aggregate = try repo.aggregate(person)
        let resolved = try PersonAggregateResolver.resolveTasks(ids: aggregate.tasks, in: context)
        #expect(resolved.map(\.id) == [live.id])
    }

    @MainActor
    @Test("Empty endpoint list resolves to no rows without touching the store")
    func emptyResolvesEmpty() throws {
        let context = try makeContext()
        #expect(try PersonAggregateResolver.resolveTasks(ids: [], in: context).isEmpty)
        #expect(try PersonAggregateResolver.resolveNotes(ids: [], in: context).isEmpty)
    }

    @MainActor
    @Test("Batched meeting counts tally attendee edges per person in one pass")
    func batchedMeetingCounts() throws {
        let context = try makeContext()
        let repo = PersonRepository(context: context)

        let alice = try repo.create(displayName: "Alice")
        let bob = try repo.create(displayName: "Bob")
        let carol = try repo.create(displayName: "Carol")  // no meetings

        let m1 = UUID()
        let m2 = UUID()
        try repo.linkAttendee(meetingID: m1, personID: alice.id)
        try repo.linkAttendee(meetingID: m2, personID: alice.id)
        try repo.linkAttendee(meetingID: m1, personID: bob.id)
        // A mention edge must NOT be counted as a meeting.
        let task = TaskItem(title: "t")
        context.insert(task)
        try context.save()
        try repo.linkMention(source: .task, sourceID: task.id, personID: bob.id)

        let counts = try PersonAggregateResolver.meetingCounts(in: context)
        #expect(counts[alice.id] == 2)
        #expect(counts[bob.id] == 1)
        #expect(counts[carol.id] == nil)
    }
}
