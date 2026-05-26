import Foundation
import NexusCore
import SwiftData
import TasksFeature
import Testing

@testable import NexusMeetings

@MainActor
@Test func importerIsIdempotent() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let importer = CirclebackImporter(
        meetingRepository: MeetingRepository(context: context),
        taskRepository: TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now }),
        linkRepository: LinkRepository(context: context)
    )
    let bundle = try MeetingsTestSupport.bundleURL(forFixture: "nexus-export")

    let first = try await importer.execute(bundleURL: bundle, progress: { _ in })
    #expect(first.importedCount == 2)

    let second = try await importer.execute(bundleURL: bundle, progress: { _ in })
    #expect(second.importedCount == 0)
    #expect(second.skippedCount >= 2)

    let count = try MeetingRepository(context: context).allChronological().count
    #expect(count == 2)
}

@MainActor
@Test func importerMapsDoneActionItems() async throws {
    let context = try MeetingsTestSupport.makeContext()
    let importer = CirclebackImporter(
        meetingRepository: MeetingRepository(context: context),
        taskRepository: TaskItemRepository(context: context, scheduler: RRuleScheduler(), now: { .now }),
        linkRepository: LinkRepository(context: context)
    )
    let bundle = try MeetingsTestSupport.bundleURL(forFixture: "nexus-export")

    let result = try await importer.execute(bundleURL: bundle, progress: { _ in })
    #expect(result.actionItemsAlreadyDone >= 1)

    let importedIDs = try TaskItemRepository(
        context: context,
        scheduler: RRuleScheduler(),
        now: { .now }
    ).allExternalSourceIDs(withPrefix: CirclebackExternalRef.actionItemPrefix)
    #expect(!importedIDs.isEmpty)

    let allTasks = try context.fetch(FetchDescriptor<TaskItem>())
    let done = allTasks.filter {
        $0.statusRaw == TaskStatus.done.rawValue
            && $0.externalSourceID?.hasPrefix(CirclebackExternalRef.actionItemPrefix) == true
    }
    #expect(!done.isEmpty)
}
