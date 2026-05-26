import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

private struct EchoTool: AgentTool {
    let name = "echo"
    let description = "Echoes input."
    let inputSchema: JSONSchema = .object(properties: [:], required: [])

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue { args }
}

private struct NoopMutatingTool: MutatingAgentTool {
    let name = "noop.mutate"
    let description = "Test mutating tool."
    let inputSchema: JSONSchema = .object(properties: [:], required: [])

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue { args }

    @MainActor
    func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction {
        let data = try JSONEncoder().encode(input)
        return InverseAction(toolName: "noop.unmutate", inputJSON: data)
    }
}

private struct ThrowingInverseTool: MutatingAgentTool {
    let name = "throwing.inverse"
    let description = "Throws while building inverse."
    let inputSchema: JSONSchema = .object(properties: [:], required: [])
    let recorder: CallRecorder

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        await recorder.recordCall()
        return args
    }

    @MainActor
    func inverse(input: JSONValue, context: AgentContext) async throws -> InverseAction {
        throw ToolDispatcherTestError.inverse
    }
}

private struct ThrowingCallTool: AgentTool {
    let name = "throwing.call"
    let description = "Throws during call."
    let inputSchema: JSONSchema = .object(properties: [:], required: [])

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        throw ToolDispatcherTestError.call
    }
}

private enum ToolDispatcherTestError: Error, Equatable {
    case call
    case inverse
}

private actor CallRecorder {
    private(set) var callCount = 0

    func recordCall() {
        callCount += 1
    }
}

@MainActor
struct ToolDispatcherTests {
    @Test
    func dispatcherRunsReadOnlyToolWithoutInverse() async throws {
        let harness = try TestHarness.make(registry: ToolRegistry(tools: [EchoTool()]))
        let input: JSONValue = .object(["text": .string("hi")])
        let threadID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_777_000_000)

        let result = try await harness.dispatcher.dispatch(
            toolName: "echo",
            input: input,
            threadID: threadID,
            now: timestamp
        )

        #expect(result.output == input)
        #expect(try JSONDecoder().decode(JSONValue.self, from: result.outputJSON) == input)

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.count == 1)
        let log = try #require(logs.first)
        #expect(log.id == result.auditLogID)
        #expect(log.timestamp == timestamp)
        #expect(log.threadID == threadID)
        #expect(log.toolName == "echo")
        #expect(log.inverseAction == nil)
        #expect(try JSONDecoder().decode(JSONValue.self, from: log.inputJSON) == input)
        #expect(try JSONDecoder().decode(JSONValue.self, from: log.outputJSON) == input)
    }

    @Test
    func dispatcherWritesStableInputAndOutputJSON() async throws {
        let harness = try TestHarness.make(registry: ToolRegistry(tools: [EchoTool()]))
        let input: JSONValue = .object(["z": .int(3), "a": .int(1), "m": .int(2)])

        let result = try await harness.dispatcher.dispatch(
            toolName: "echo",
            input: input,
            threadID: nil
        )

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        let log = try #require(logs.first)
        let expectedJSON = Data(#"{"a":1,"m":2,"z":3}"#.utf8)
        #expect(log.inputJSON == expectedJSON)
        #expect(log.outputJSON == expectedJSON)
        #expect(result.outputJSON == expectedJSON)
    }

    @Test
    func dispatcherWritesInverseForMutatingTool() async throws {
        let harness = try TestHarness.make(registry: ToolRegistry(tools: [NoopMutatingTool()]))
        let input: JSONValue = .object(["x": .int(1)])

        let result = try await harness.dispatcher.dispatch(
            toolName: "noop.mutate",
            input: input,
            threadID: nil
        )

        #expect(result.output == input)

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.count == 1)
        let log = try #require(logs.first)
        #expect(log.toolName == "noop.mutate")
        let inverseData = try #require(log.inverseAction)
        let inverseAction = try JSONDecoder().decode(InverseAction.self, from: inverseData)
        #expect(inverseAction.toolName == "noop.unmutate")
        #expect(try JSONDecoder().decode(JSONValue.self, from: inverseAction.inputJSON) == input)
    }

    @Test
    func dispatcherDoesNotCallMutatingToolOrAuditWhenInverseThrows() async throws {
        let recorder = CallRecorder()
        let harness = try TestHarness.make(
            registry: ToolRegistry(tools: [ThrowingInverseTool(recorder: recorder)])
        )
        let input: JSONValue = .object(["x": .int(1)])

        await #expect(throws: ToolDispatcherTestError.inverse) {
            try await harness.dispatcher.dispatch(
                toolName: "throwing.inverse",
                input: input,
                threadID: nil
            )
        }

        #expect(await recorder.callCount == 0)
        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.isEmpty)
    }

    @Test
    func dispatcherDoesNotAuditWhenToolCallThrows() async throws {
        let harness = try TestHarness.make(registry: ToolRegistry(tools: [ThrowingCallTool()]))
        let input: JSONValue = .object(["x": .int(1)])

        await #expect(throws: ToolDispatcherTestError.call) {
            try await harness.dispatcher.dispatch(
                toolName: "throwing.call",
                input: input,
                threadID: nil
            )
        }

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.isEmpty)
    }

    @Test
    func dispatcherThrowsForMissingToolWithoutAuditLog() async throws {
        let harness = try TestHarness.make(registry: ToolRegistry(tools: [EchoTool()]))
        let input: JSONValue = .object(["text": .string("hi")])

        await #expect(throws: ToolDispatcherError.toolNotFound("missing")) {
            try await harness.dispatcher.dispatch(
                toolName: "missing",
                input: input,
                threadID: nil
            )
        }

        let logs = try harness.modelContext.fetch(FetchDescriptor<AgentAuditLog>())
        #expect(logs.isEmpty)
    }
}

@MainActor
private struct TestHarness {
    let dispatcher: ToolDispatcher
    let modelContext: ModelContext

    static func make(registry: ToolRegistry) throws -> TestHarness {
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
        let dispatcher = ToolDispatcher(
            registry: registry,
            modelContext: modelContext,
            agentContext: agentContext
        )
        return TestHarness(dispatcher: dispatcher, modelContext: modelContext)
    }
}
