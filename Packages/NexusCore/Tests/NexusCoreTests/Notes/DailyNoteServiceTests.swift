import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
struct DailyNoteServiceTests {
    // MARK: - Harness (mirrors NoteReconcilerTests.makeContext)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeService() throws -> (service: DailyNoteService, repository: NoteRepository) {
        let schema = Schema([Note.self, TaskItem.self, Link.self, Project.self, Section.self])
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [config])
        let repository = NoteRepository(context: ModelContext(container))
        return (DailyNoteService(repository: repository, calendar: utc), repository)
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    private func liveNotes(_ repository: NoteRepository) throws -> [Note] {
        try repository.context.fetch(FetchDescriptor<Note>()).filter { $0.deletedAt == nil }
    }

    // MARK: - openOrCreate

    @Test func openOrCreateCreatesConventionNote() throws {
        let (service, repository) = try makeService()

        let note = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(note.title == "Daily Brief 2026-06-11")
        #expect(note.role == .dailyNote)
        #expect(note.tags == ["daily", "2026-06-11"])
        #expect(try liveNotes(repository).count == 1)
    }

    @Test func openOrCreateIsIdempotent() throws {
        let (service, repository) = try makeService()

        let first = try service.openOrCreate(for: day(2026, 6, 11))
        let second = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(first.id == second.id)
        #expect(try liveNotes(repository).count == 1)
    }

    @Test func openOrCreateReturnsAgentCreatedNote() throws {
        // The agent's brief writer creates "Daily Brief <dayKey>" with the same
        // role/tags; "Today's note" must return THAT note, never mint a twin.
        let (service, repository) = try makeService()
        let agentNote = try repository.create(
            title: "Daily Brief 2026-06-11",
            blocks: [Block(kind: .paragraph(runs: [InlineRun(text: "Agent brief.")]))],
            role: .dailyNote,
            tags: ["daily", "2026-06-11"]
        )

        let opened = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(opened.id == agentNote.id)
        #expect(try liveNotes(repository).count == 1)
    }

    @Test func openOrCreateResolvesLegacyTwinsToOldestDeterministically() throws {
        // Legacy twin daily notes (pre-convention data or a CloudKit merge) can
        // share one title. Without an explicit fetch order SwiftData returns
        // rows in implementation-defined order, so "Today" could bounce between
        // twins across launches. Pin: the OLDEST twin (createdAt) always wins.
        let (service, repository) = try makeService()
        let newer = try repository.create(
            title: "Daily Brief 2026-06-11", blocks: [], role: .dailyNote,
            tags: ["daily", "2026-06-11"]
        )
        let older = try repository.create(
            title: "Daily Brief 2026-06-11", blocks: [], role: .dailyNote,
            tags: ["daily", "2026-06-11"]
        )
        // Inserted newer-first to bias against insertion-order luck; identity
        // must come from createdAt, not fetch order.
        newer.createdAt = day(2026, 6, 11).addingTimeInterval(3600)
        older.createdAt = day(2026, 6, 11)
        try repository.context.save()

        for _ in 0..<5 {
            #expect(try service.openOrCreate(for: day(2026, 6, 11)).id == older.id)
        }
        #expect(try liveNotes(repository).count == 2, "resolution must not mint a third twin")
    }

    @Test func openOrCreateIgnoresSoftDeletedDailyNote() throws {
        let (service, repository) = try makeService()
        let deleted = try service.openOrCreate(for: day(2026, 6, 11))
        try repository.delete(deleted)

        let recreated = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(recreated.id != deleted.id)
        #expect(recreated.deletedAt == nil)
    }

    @Test func openOrCreateDistinguishesDays() throws {
        let (service, repository) = try makeService()

        let wednesday = try service.openOrCreate(for: day(2026, 6, 10))
        let thursday = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(wednesday.id != thursday.id)
        #expect(try liveNotes(repository).count == 2)
    }

    // MARK: - day(of:)

    @Test func dayOfDecodesConventionTitle() throws {
        let (service, _) = try makeService()
        let note = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(service.day(of: note) == day(2026, 6, 11))
    }

    @Test func dayOfIsNilForFreeNotes() throws {
        let (service, repository) = try makeService()
        let free = try repository.create(
            title: "Daily Brief 2026-06-11", blocks: [], role: .free
        )

        #expect(service.day(of: free) == nil)
    }

    // MARK: - adjacent lookup

    @Test func adjacentSkipsGapsBothWays() throws {
        let (service, _) = try makeService()
        let monday = try service.openOrCreate(for: day(2026, 6, 8))
        let thursday = try service.openOrCreate(for: day(2026, 6, 11))
        let friday = try service.openOrCreate(for: day(2026, 6, 12))

        // Tue+Wed missing: previous-from-Thursday jumps the gap back to Monday.
        #expect(try service.adjacentDailyNote(from: thursday, direction: .previous)?.id == monday.id)
        #expect(try service.adjacentDailyNote(from: thursday, direction: .next)?.id == friday.id)
        #expect(try service.adjacentDailyNote(from: friday, direction: .previous)?.id == thursday.id)
    }

    @Test func adjacentIsNilAtTheEdges() throws {
        let (service, _) = try makeService()
        let only = try service.openOrCreate(for: day(2026, 6, 11))

        #expect(try service.adjacentDailyNote(from: only, direction: .previous) == nil)
        #expect(try service.adjacentDailyNote(from: only, direction: .next) == nil)
    }

    @Test func adjacentIgnoresNonDailyAndOffConventionNotes() throws {
        let (service, repository) = try makeService()
        let thursday = try service.openOrCreate(for: day(2026, 6, 11))
        // A free note titled like a daily note, and a daily note with a custom
        // title: neither participates in date navigation.
        _ = try repository.create(title: "Daily Brief 2026-06-10", blocks: [], role: .free)
        _ = try repository.create(title: "Scratchpad", blocks: [], role: .dailyNote)

        #expect(try service.adjacentDailyNote(from: thursday, direction: .previous) == nil)
        #expect(try service.adjacentDailyNote(from: thursday, direction: .next) == nil)
    }
}
