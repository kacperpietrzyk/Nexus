import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("ActivityRecorder")
@MainActor
struct ActivityRecorderTests {

    private func makeContext() throws -> ModelContext {
        let schema = Schema([ActivityEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }

    @Test("record inserts an entry with the given fields and stamped now")
    func recordInsertsEntry() throws {
        let context = try makeContext()
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let recorder = ActivityRecorder(context: context, now: { stamp })
        let taskID = UUID()

        recorder.record(.completed, itemID: taskID, itemKind: .task, payloadJSON: nil)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<ActivityEntry>())
        #expect(entries.count == 1)
        #expect(entries.first?.itemID == taskID)
        #expect(entries.first?.itemKindRaw == ItemKind.task.rawValue)
        #expect(entries.first?.eventKindRaw == ActivityEventKind.completed.rawValue)
        #expect(entries.first?.payloadJSON == nil)
        #expect(entries.first?.createdAt == stamp)
    }

    @Test("recorder NEVER saves — a rollback discards the un-saved entry (I-B1)")
    func recorderNeverSaves() throws {
        let context = try makeContext()
        let recorder = ActivityRecorder(context: context)

        recorder.record(.created, itemID: UUID(), itemKind: .task, payloadJSON: nil)
        context.rollback()

        let entries = try context.fetch(FetchDescriptor<ActivityEntry>())
        #expect(entries.isEmpty)
    }

    @Test("recordChange encodes an old/new payload")
    func recordChangeEncodesPayload() throws {
        let context = try makeContext()
        let recorder = ActivityRecorder(context: context)

        recorder.recordChange(.workflowChanged, itemID: UUID(), itemKind: .task, old: "todo", new: "inProgress")
        try context.save()

        let entries = try context.fetch(FetchDescriptor<ActivityEntry>())
        let payload = ActivityChangePayload.decoded(from: entries.first?.payloadJSON)
        #expect(payload == ActivityChangePayload(old: "todo", new: "inProgress"))
    }

    @Test("NoopActivityRecorder inserts nothing")
    func noopInsertsNothing() throws {
        let context = try makeContext()
        let noop = NoopActivityRecorder()

        noop.record(.created, itemID: UUID(), itemKind: .task, payloadJSON: nil)
        try context.save()

        let entries = try context.fetch(FetchDescriptor<ActivityEntry>())
        #expect(entries.isEmpty)
    }
}
