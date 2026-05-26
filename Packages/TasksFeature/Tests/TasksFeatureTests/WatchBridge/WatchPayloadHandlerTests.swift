import Foundation
import NexusCore
import SwiftData
import Testing

@testable import TasksFeature

@Suite("WatchPayloadHandler")
struct WatchPayloadHandlerTests {
    private struct FixedParser: NLParser {
        let result: ParseResult

        func parse(_: String, locale _: Locale, now _: Date, calendar _: Calendar) async -> ParseResult {
            result
        }
    }

    @MainActor
    private func makeRepository() throws -> TaskItemRepository {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        return TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { .now }
        )
    }

    @MainActor
    @Test("Capture payload inserts a task")
    func capturePayloadInserts() async throws {
        let repository = try makeRepository()
        let endAt = Date(timeIntervalSince1970: 1_778_162_400)
        let deadlineAt = Date(timeIntervalSince1970: 1_778_508_000)
        let parser = FixedParser(
            result: ParseResult(
                title: "Buy milk",
                endAt: endAt,
                deadlineAt: deadlineAt,
                confidence: 1.0
            ))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.captureType,
            WatchPayload.inputKey: "kup mleko",
            WatchPayload.idKey: UUID().uuidString,
        ])

        #expect(outcome == .inserted)

        let stored = try repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.count == 1)
        #expect(stored.first?.title == "Buy milk")
        #expect(stored.first?.endAt == endAt)
        #expect(stored.first?.deadlineAt == deadlineAt)
    }

    @MainActor
    @Test("Empty input is ignored")
    func emptyInputIgnored() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: ""))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.captureType,
            WatchPayload.inputKey: "   ",
        ])

        #expect(outcome == .ignored)
        let stored = try repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.isEmpty)
    }

    @MainActor
    @Test("Unknown payload type is ignored")
    func unknownTypeIgnored() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: ["type": "ping"])

        #expect(outcome == .ignored)
        let stored = try repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.isEmpty)
    }

    @MainActor
    @Test("Ask Nexus payload is ignored without agent handler")
    func askNexusIgnoredWithoutHandler() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.askNexusType,
            WatchPayload.promptKey: "Co dalej?",
        ])

        #expect(outcome == .ignored)
        let stored = try repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.isEmpty)
    }

    @MainActor
    @Test("Ask Nexus payload routes to agent handler")
    func askNexusRoutesToAgentHandler() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(
            parser: parser,
            repository: repository,
            agentPromptHandler: { prompt in
                #expect(prompt == "Co dalej?")
                return "Krótka odpowiedź"
            }
        )

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.askNexusType,
            WatchPayload.promptKey: "  Co dalej?  ",
        ])

        #expect(outcome == .replied("Krótka odpowiedź"))
        let stored = try repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.isEmpty)
    }

    @MainActor
    @Test("Ask Nexus handler errors return failed outcome")
    func askNexusHandlerErrorReturnsFailed() async throws {
        struct AgentFailure: Error, CustomStringConvertible {
            let description = "provider failed"
        }

        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(
            parser: parser,
            repository: repository,
            agentPromptHandler: { _ in throw AgentFailure() }
        )

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.askNexusType,
            WatchPayload.promptKey: "Co dalej?",
        ])

        #expect(outcome == .failed("provider failed"))
    }

    @MainActor
    @Test("Mark-done payload runs markDone on existing task")
    func markDoneRoutes() async throws {
        let repository = try makeRepository()
        let task = TaskItem(title: "x", dueAt: .now)
        try repository.insert(task)
        let parser = FixedParser(result: ParseResult(title: "ignored"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.markDoneType,
            WatchPayload.taskIDKey: task.id.uuidString,
            WatchPayload.idKey: UUID().uuidString,
        ])

        #expect(outcome == .updated)
        #expect(task.statusRaw == TaskStatus.done.rawValue)
    }

    @MainActor
    @Test("Mark-done payload cascades open subtasks")
    func markDoneCascadesOpenSubtasks() async throws {
        let repository = try makeRepository()
        let parent = TaskItem(title: "parent", dueAt: .now)
        let child = TaskItem(title: "child", parentTaskID: parent.id)
        try repository.insert(parent)
        try repository.insert(child)
        let parser = FixedParser(result: ParseResult(title: "ignored"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.markDoneType,
            WatchPayload.taskIDKey: parent.id.uuidString,
            WatchPayload.idKey: UUID().uuidString,
        ])

        #expect(outcome == .updated)
        #expect(parent.status == .done)
        #expect(child.status == .done)
    }

    @MainActor
    @Test("Reopen payload runs reopen on existing task")
    func reopenRoutes() async throws {
        let repository = try makeRepository()
        let task = TaskItem(title: "x", dueAt: .now)
        try repository.insert(task)
        try repository.markDone(task)
        let parser = FixedParser(result: ParseResult(title: "ignored"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.reopenType,
            WatchPayload.taskIDKey: task.id.uuidString,
        ])

        #expect(outcome == .updated)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.lastCompletedAt == nil)
    }

    @MainActor
    @Test("Mark-done with missing taskID is ignored")
    func markDoneMissingTaskID() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.markDoneType
        ])

        #expect(outcome == .ignored)
    }

    @MainActor
    @Test("Mark-done with malformed taskID is ignored")
    func markDoneMalformedTaskID() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.markDoneType,
            WatchPayload.taskIDKey: "not-a-uuid",
        ])

        #expect(outcome == .ignored)
    }

    @MainActor
    @Test("Mark-done with unknown taskID is ignored")
    func markDoneUnknownTaskID() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.markDoneType,
            WatchPayload.taskIDKey: UUID().uuidString,
        ])

        #expect(outcome == .ignored)
    }

    @MainActor
    @Test("Mark-done with soft-deleted taskID is ignored")
    func markDoneSoftDeletedTaskID() async throws {
        let repository = try makeRepository()
        let task = TaskItem(title: "x", dueAt: .now, recurrenceRule: "FREQ=DAILY")
        try repository.insert(task)
        try repository.softDelete(task)
        let parser = FixedParser(result: ParseResult(title: "x"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.markDoneType,
            WatchPayload.taskIDKey: task.id.uuidString,
        ])

        #expect(outcome == .ignored)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.lastCompletedAt == nil)
        let stored = try repository.context.fetch(FetchDescriptor<TaskItem>())
        #expect(stored.count == 1)
    }
}

@Suite("WatchPayloadHandler snooze action")
struct WatchPayloadHandlerSnoozeTests {
    private struct FixedParser: NLParser {
        let result: ParseResult

        func parse(_: String, locale _: Locale, now _: Date, calendar _: Calendar) async -> ParseResult {
            result
        }
    }

    @MainActor
    private func makeRepository() throws -> TaskItemRepository {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        return TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { .now }
        )
    }

    @MainActor
    @Test("Snooze action routes to repository.snooze")
    func snoozeActionRoutes() async throws {
        let repository = try makeRepository()
        let task = TaskItem(title: "x", dueAt: Date().addingTimeInterval(60))
        try repository.insert(task)
        let parser = FixedParser(result: ParseResult(title: "ignored"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let until = Date().addingTimeInterval(3_600)
        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.snoozeActionType,
            WatchPayload.taskIDKey: task.id.uuidString,
            WatchPayload.snoozeUntilKey: ISO8601DateFormatter().string(from: until),
        ])

        #expect(outcome == .updated)
        #expect(task.statusRaw == TaskStatus.snoozed.rawValue)
        #expect(abs((task.snoozedUntil ?? .distantPast).timeIntervalSince(until)) < 1)
    }

    @MainActor
    @Test("Snooze action with missing until is ignored")
    func snoozeMissingUntil() async throws {
        let repository = try makeRepository()
        let task = TaskItem(title: "x", dueAt: Date().addingTimeInterval(60))
        try repository.insert(task)
        let parser = FixedParser(result: ParseResult(title: "ignored"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.snoozeActionType,
            WatchPayload.taskIDKey: task.id.uuidString,
        ])

        #expect(outcome == .ignored)
        #expect(task.statusRaw == TaskStatus.open.rawValue)
        #expect(task.snoozedUntil == nil)
    }

    @MainActor
    @Test("Snooze action with missing taskID is ignored")
    func snoozeMissingTaskID() async throws {
        let repository = try makeRepository()
        let parser = FixedParser(result: ParseResult(title: "ignored"))
        let handler = WatchPayloadHandler(parser: parser, repository: repository)

        let until = Date().addingTimeInterval(3_600)
        let outcome = await handler.handle(payload: [
            WatchPayload.typeKey: WatchPayload.snoozeActionType,
            WatchPayload.snoozeUntilKey: ISO8601DateFormatter().string(from: until),
        ])

        #expect(outcome == .ignored)
    }
}
