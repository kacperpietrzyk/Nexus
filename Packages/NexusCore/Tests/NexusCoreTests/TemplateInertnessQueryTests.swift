import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("I-D1 template inertness — query sweep")
struct TemplateInertnessQueryTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            TaskItem.self, Note.self, Link.self, Project.self,
            SavedFilter.self, ScheduledBlock.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        comps.hour = hour
        return Calendar.gregorianUTC.date(from: comps)!
    }

    @MainActor
    @Test("TodayQuery buckets exclude templates")
    func todayBucketsExcludeTemplates() throws {
        let context = try makeContext()
        let now = date(2026, 6, 11, hour: 14)
        context.insert(TaskItem(title: "live overdue", dueAt: date(2026, 6, 10)))
        context.insert(TaskItem(title: "live today", dueAt: date(2026, 6, 11)))
        context.insert(TaskItem(title: "live nodate"))
        context.insert(TaskItem(title: "tpl overdue", dueAt: date(2026, 6, 10), isTemplate: true))
        context.insert(TaskItem(title: "tpl today", dueAt: date(2026, 6, 11), isTemplate: true))
        context.insert(TaskItem(title: "tpl nodate", isTemplate: true))
        try context.save()

        let query = TodayQuery(calendar: .gregorianUTC)
        #expect(try query.overdue(now: now).apply(in: context).map(\.title) == ["live overdue"])
        #expect(try query.today(now: now).apply(in: context).map(\.title) == ["live today"])
        #expect(try query.noDate().apply(in: context).map(\.title) == ["live nodate"])
    }

    @MainActor
    @Test("TodayQuery.awaiting never surfaces a blocking template")
    func awaitingExcludesTemplates() throws {
        let context = try makeContext()
        let blocked = TaskItem(title: "blocked")
        let template = TaskItem(title: "tpl blocker", isTemplate: true)
        context.insert(blocked)
        context.insert(template)
        try context.save()
        let links = LinkRepository(context: context)
        try links.create(from: (.task, template.id), to: (.task, blocked.id), linkKind: .blocks)

        let entries = try TodayQuery(calendar: .gregorianUTC)
            .awaiting(now: date(2026, 6, 11), modelContext: context, linkRepository: links)
        #expect(entries.isEmpty)
    }

    @MainActor
    @Test("UpcomingQuery excludes templates")
    func upcomingExcludesTemplates() throws {
        let context = try makeContext()
        let now = date(2026, 6, 11)
        context.insert(TaskItem(title: "live", dueAt: date(2026, 6, 13)))
        context.insert(TaskItem(title: "tpl", dueAt: date(2026, 6, 13), isTemplate: true))
        try context.save()

        let tasks = try UpcomingQuery(calendar: .gregorianUTC)
            .next(days: 7, from: now)
            .apply(in: context)
        #expect(tasks.map(\.title) == ["live"])
    }

    @MainActor
    @Test("ByTagQuery excludes templates")
    func byTagExcludesTemplates() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "live", tags: ["work"]))
        context.insert(TaskItem(title: "tpl", tags: ["work"], isTemplate: true))
        try context.save()

        let tasks = try ByTagQuery().tasks(withTag: "work").apply(in: context)
        #expect(tasks.map(\.title) == ["live"])
    }

    @MainActor
    @Test("SavedFilterRepository.apply excludes templates")
    func savedFilterExcludesTemplates() throws {
        let context = try makeContext()
        context.insert(TaskItem(title: "live", tags: ["work"]))
        context.insert(TaskItem(title: "tpl", tags: ["work"], isTemplate: true))
        try context.save()

        let repo = SavedFilterRepository(context: context, now: { self.date(2026, 6, 11) })
        let filter = try repo.create(name: "Work", definition: .byTag("work"))
        let tasks = try repo.apply(filter, now: date(2026, 6, 11))
        #expect(tasks.map(\.title) == ["live"])
    }

    @Test("DayPlanCandidates excludes templates, even pinned ones")
    func dayPlanCandidatesExcludeTemplates() {
        let now = date(2026, 6, 11, hour: 9)
        let live = TaskItem(title: "live", dueAt: date(2026, 6, 11))
        let dueTemplate = TaskItem(title: "tpl due", dueAt: date(2026, 6, 11), isTemplate: true)
        let pinnedTemplate = TaskItem(title: "tpl pinned", pinnedAsFocus: true, isTemplate: true)

        let selected = DayPlanCandidates.select(
            from: [live, dueTemplate, pinnedTemplate],
            now: now,
            calendar: .gregorianUTC
        )
        #expect(selected.map(\.title) == ["live"])
    }

    @MainActor
    @Test("DailyRolloverJob never rolls a template's dueAt")
    func rolloverSkipsTemplates() async throws {
        let schema = Schema([TaskItem.self, ScheduledBlock.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let overdue = date(2026, 6, 8)
        let live = TaskItem(title: "live", dueAt: overdue)
        let template = TaskItem(title: "tpl", dueAt: overdue, isTemplate: true)
        context.insert(live)
        context.insert(template)
        try context.save()

        try await DailyRolloverJob.rollover(in: container, now: date(2026, 6, 11), calendar: .gregorianUTC)

        let all = try ModelContext(container).fetch(FetchDescriptor<TaskItem>())
        let rolledLive = all.first { $0.title == "live" }
        let keptTemplate = all.first { $0.title == "tpl" }
        #expect((rolledLive?.dueAt ?? .distantPast) > overdue)
        #expect(keptTemplate?.dueAt == overdue)
    }

    @MainActor
    @Test("TaskTemplateQuery returns root templates only, sorted by title")
    func taskTemplateQueryReturnsRootTemplates() throws {
        let context = try makeContext()
        let rootB = TaskItem(title: "B template", isTemplate: true)
        let rootA = TaskItem(title: "A template", isTemplate: true)
        let child = TaskItem(title: "child", parentTaskID: rootA.id, isTemplate: true)
        let live = TaskItem(title: "live")
        let deleted = TaskItem(title: "deleted", isTemplate: true)
        deleted.deletedAt = .now
        for task in [rootB, rootA, child, live, deleted] { context.insert(task) }
        try context.save()

        let templates = try TaskTemplateQuery.rootTemplates(in: context)
        #expect(templates.map(\.title) == ["A template", "B template"])
    }
}
