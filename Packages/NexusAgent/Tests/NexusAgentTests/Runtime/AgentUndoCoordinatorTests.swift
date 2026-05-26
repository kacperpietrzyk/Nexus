import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

private struct IncrementTool: MutatingAgentTool {
    let name = "counter.increment"
    let description = "Increment a counter."
    let inputSchema: JSONSchema = .object(
        properties: ["by": .integer(description: "Amount to increment by.")],
        required: ["by"]
    )
    let recorder: CounterRecorder?

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        await recorder?.record(toolName: name, args: args)
        return args
    }

    @MainActor
    func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction {
        let inputJSON = try JSONEncoder().encode(input)
        return InverseAction(toolName: "counter.decrement", inputJSON: inputJSON)
    }
}

private struct DecrementTool: MutatingAgentTool {
    let name = "counter.decrement"
    let description = "Decrement a counter."
    let inputSchema: JSONSchema = .object(
        properties: ["by": .integer(description: "Amount to decrement by.")],
        required: ["by"]
    )
    let recorder: CounterRecorder

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        await recorder.record(toolName: name, args: args)
        return args
    }

    @MainActor
    func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction {
        let inputJSON = try JSONEncoder().encode(input)
        return InverseAction(toolName: "counter.increment", inputJSON: inputJSON)
    }
}

private actor CounterRecorder {
    private var calls: [CounterCall] = []
    private var pauseNextCall: Bool
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(pauseNextCall: Bool = false) {
        self.pauseNextCall = pauseNextCall
    }

    func record(toolName: String, args: JSONValue) async {
        calls.append(CounterCall(toolName: toolName, args: args))
        waiters.forEach { $0.resume() }
        waiters.removeAll()

        if pauseNextCall {
            pauseNextCall = false
            await withCheckedContinuation { continuation in
                pauseContinuation = continuation
            }
        }
    }

    func recordedInputs(for toolName: String) -> [JSONValue] {
        calls.compactMap { call in
            call.toolName == toolName ? call.args : nil
        }
    }

    func waitForCallCount(_ count: Int) async {
        if calls.count >= count { return }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releasePausedCall() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}

private struct CounterCall: Equatable, Sendable {
    let toolName: String
    let args: JSONValue
}

@MainActor
struct AgentUndoCoordinatorTests {
    @Test
    func singleUndoMarksOriginalLogAndCreatesInverseDispatchLog() async throws {
        let recorder = CounterRecorder()
        let harness = try TestHarness.make(recorder: recorder)
        let threadID = UUID()
        let input: JSONValue = .object(["by": .int(1)])
        let originalTime = Date(timeIntervalSince1970: 1_777_000_000)
        let undoTime = Date(timeIntervalSince1970: 1_777_000_100)

        let result = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: input,
            threadID: threadID,
            now: originalTime
        )

        try await harness.coordinator.undo(auditLogID: result.auditLogID, now: undoTime)

        let logs = try harness.fetchAuditLogs()
        #expect(logs.count == 2)

        let original = try #require(logs.first { $0.id == result.auditLogID })
        #expect(original.undoneAt == undoTime)

        let inverseLog = try #require(logs.first { $0.id != result.auditLogID })
        #expect(inverseLog.toolName == "counter.decrement")
        #expect(inverseLog.threadID == threadID)
        #expect(inverseLog.inverseAction != nil)
        #expect(inverseLog.undoneAt == undoTime)
        #expect(try JSONDecoder().decode(JSONValue.self, from: inverseLog.inputJSON) == input)
        #expect(await recorder.recordedInputs(for: "counter.decrement") == [input])
    }

    @Test
    func bulkUndoThreadReversesEligibleEntriesInReverseChronologicalOrder() async throws {
        let recorder = CounterRecorder()
        let harness = try TestHarness.make(recorder: recorder)
        let threadID = UUID()
        let unrelatedThreadID = UUID()
        let undoTime = Date(timeIntervalSince1970: 1_777_000_100)
        let firstInput: JSONValue = .object(["by": .int(1)])
        let secondInput: JSONValue = .object(["by": .int(2)])
        let thirdInput: JSONValue = .object(["by": .int(3)])

        let first = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: firstInput,
            threadID: threadID,
            now: Date(timeIntervalSince1970: 1_777_000_001)
        )
        let second = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: secondInput,
            threadID: threadID,
            now: Date(timeIntervalSince1970: 1_777_000_002)
        )
        let third = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: thirdInput,
            threadID: threadID,
            now: Date(timeIntervalSince1970: 1_777_000_003)
        )
        _ = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: .object(["by": .int(99)]),
            threadID: unrelatedThreadID,
            now: Date(timeIntervalSince1970: 1_777_000_004)
        )

        try await harness.coordinator.undoAll(threadID: threadID, now: undoTime)

        let logs = try harness.fetchAuditLogs()
        let originals = logs.filter { [first.auditLogID, second.auditLogID, third.auditLogID].contains($0.id) }
        #expect(originals.count == 3)
        #expect(originals.allSatisfy { $0.undoneAt == undoTime })

        let unrelated = try #require(logs.first { $0.threadID == unrelatedThreadID })
        #expect(unrelated.undoneAt == nil)

        let inverseLogs = logs.filter { $0.threadID == threadID && $0.toolName == "counter.decrement" }
        #expect(inverseLogs.count == 3)
        #expect(inverseLogs.allSatisfy { $0.undoneAt == undoTime })
        #expect(await recorder.recordedInputs(for: "counter.decrement") == [thirdInput, secondInput, firstInput])
    }

    @Test
    func concurrentUndoOnlyDispatchesOneInverse() async throws {
        let recorder = CounterRecorder(pauseNextCall: true)
        let harness = try TestHarness.make(recorder: recorder)
        let input: JSONValue = .object(["by": .int(1)])
        let result = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: input,
            threadID: UUID()
        )

        let firstUndo = Task { @MainActor in
            do {
                try await harness.coordinator.undo(auditLogID: result.auditLogID)
                return true
            } catch {
                return false
            }
        }
        await recorder.waitForCallCount(1)
        let secondUndo = Task { @MainActor in
            do {
                try await harness.coordinator.undo(auditLogID: result.auditLogID)
                return true
            } catch AgentUndoError.undoInProgress(result.auditLogID) {
                return false
            } catch AgentUndoError.alreadyUndone(result.auditLogID) {
                return false
            } catch {
                Issue.record("Unexpected undo error: \(error)")
                return false
            }
        }

        let secondSucceeded = await secondUndo.value
        await recorder.releasePausedCall()
        let firstSucceeded = await firstUndo.value

        #expect(firstSucceeded != secondSucceeded)
        #expect(await recorder.recordedInputs(for: "counter.decrement") == [input])

        let original = try #require(try harness.fetchAuditLogs().first { $0.id == result.auditLogID })
        #expect(original.undoneAt != nil)
    }

    @Test
    func bulkUndoDoesNotPickUpUndoGeneratedMutatingInverseLogs() async throws {
        let decrementRecorder = CounterRecorder()
        let incrementRecorder = CounterRecorder()
        let harness = try TestHarness.make(
            recorder: decrementRecorder,
            incrementRecorder: incrementRecorder
        )
        let threadID = UUID()
        let input: JSONValue = .object(["by": .int(1)])
        let result = try await harness.dispatcher.dispatch(
            toolName: "counter.increment",
            input: input,
            threadID: threadID
        )

        try await harness.coordinator.undoAll(threadID: threadID)
        try await harness.coordinator.undoAll(threadID: threadID)

        let logs = try harness.fetchAuditLogs()
        let original = try #require(logs.first { $0.id == result.auditLogID })
        #expect(original.undoneAt != nil)
        #expect(await decrementRecorder.recordedInputs(for: "counter.decrement") == [input])
        #expect(await incrementRecorder.recordedInputs(for: "counter.increment") == [input])
        #expect(
            logs.filter {
                $0.threadID == threadID && $0.undoneAt == nil && $0.inverseAction != nil
            }.isEmpty
        )
    }

    @Test
    func undoThrowsWhenAuditLogIsMissing() async throws {
        let harness = try TestHarness.make(recorder: CounterRecorder())
        let missingID = UUID()

        await #expect(throws: AgentUndoError.auditLogNotFound(missingID)) {
            try await harness.coordinator.undo(auditLogID: missingID)
        }
    }

    @Test
    func undoThrowsWhenEntryAlreadyUndone() async throws {
        let harness = try TestHarness.make(recorder: CounterRecorder())
        let logID = UUID()
        harness.modelContext.insert(
            AgentAuditLog(
                id: logID,
                toolName: "counter.increment",
                inputJSON: Data(#"{"by":1}"#.utf8),
                outputJSON: Data(#"{"by":1}"#.utf8),
                inverseAction: try JSONEncoder().encode(
                    InverseAction(toolName: "counter.decrement", inputJSON: Data(#"{"by":1}"#.utf8))
                ),
                undoneAt: Date(timeIntervalSince1970: 1_777_000_000)
            )
        )
        try harness.modelContext.save()

        await #expect(throws: AgentUndoError.alreadyUndone(logID)) {
            try await harness.coordinator.undo(auditLogID: logID)
        }
    }

    @Test
    func undoThrowsWhenNoInverseWasRecorded() async throws {
        let harness = try TestHarness.make(recorder: CounterRecorder())
        let logID = UUID()
        harness.modelContext.insert(
            AgentAuditLog(
                id: logID,
                toolName: "counter.read",
                inputJSON: Data(#"{"by":1}"#.utf8),
                outputJSON: Data(#"{"by":1}"#.utf8)
            )
        )
        try harness.modelContext.save()

        await #expect(throws: AgentUndoError.noInverseRecorded(logID)) {
            try await harness.coordinator.undo(auditLogID: logID)
        }
    }
}

@MainActor
private struct TestHarness {
    let coordinator: AgentUndoCoordinator
    let dispatcher: ToolDispatcher
    let modelContext: ModelContext

    static func make(
        recorder: CounterRecorder,
        incrementRecorder: CounterRecorder? = nil
    ) throws -> TestHarness {
        let schema = Schema([
            AgentAuditLog.self,
            Link.self,
            DebugItem.self,
            QuotaLog.self,
            TaskItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let modelContext = ModelContext(container)
        let repository = TaskItemRepository(
            context: modelContext,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(modelContext),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let registry = ToolRegistry(tools: [
            IncrementTool(recorder: incrementRecorder),
            DecrementTool(recorder: recorder),
        ])
        let dispatcher = ToolDispatcher(
            registry: registry,
            modelContext: modelContext,
            agentContext: agentContext
        )
        let coordinator = AgentUndoCoordinator(
            dispatcher: dispatcher,
            modelContext: modelContext
        )
        return TestHarness(
            coordinator: coordinator,
            dispatcher: dispatcher,
            modelContext: modelContext
        )
    }

    func fetchAuditLogs() throws -> [AgentAuditLog] {
        try modelContext.fetch(FetchDescriptor<AgentAuditLog>())
    }
}
