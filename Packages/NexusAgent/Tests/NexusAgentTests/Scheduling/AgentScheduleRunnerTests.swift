import Foundation
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData
import Testing
@preconcurrency import UserNotifications
import os

@testable import NexusAgent

@MainActor
@Suite(.serialized)
struct AgentScheduleRunnerTests {
    @Test func runnerExecutesScheduleAndUpdatesStatus() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let scheduleID = try scheduleStore.create(
            name: "Morning Brief",
            cronExpression: "0 8 * * *",
            prompt: "Zbuduj brief dnia"
        )
        let runtime = makeRuntime(
            context: context,
            threadStore: threads,
            messageStore: messages,
            responseText: "brief OK"
        )
        let runner = AgentScheduleRunner(
            runtime: runtime,
            threadStore: threads,
            scheduleStore: scheduleStore
        )

        let result = try await runner.run(scheduleID: scheduleID)

        #expect(result.status == .success)
        let updated = try #require(try scheduleStore.get(id: scheduleID))
        #expect(updated.lastRunStatus == .success)
        #expect(updated.lastRunAt != nil)
        let resultRef = try #require(updated.lastRunResultRef)
        #expect(result.resultRef == resultRef)

        let threadID = try #require(updated.threadID)
        let stored = try messages.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user, .agent])
        #expect(stored.last?.id == resultRef)
        #expect(stored.last?.content == "brief OK")
    }

    @Test func runnerSkipsWhenScheduleDisabled() async throws {
        let context = try AgentTestSupport.makeContext()
        let scheduleStore = AgentScheduleStore(context: context)
        let scheduleID = try scheduleStore.create(
            name: "Disabled",
            cronExpression: "0 8 * * *",
            prompt: "x",
            enabled: false
        )
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: AgentThreadStore(context: context),
                messageStore: AgentMessageStore(context: context),
                responseText: ""
            ),
            threadStore: AgentThreadStore(context: context),
            scheduleStore: scheduleStore
        )

        let result = try await runner.run(scheduleID: scheduleID)

        #expect(result.status == .skipped)
        #expect(result.resultRef == nil)
        #expect(result.error == nil)
        let updated = try #require(try scheduleStore.get(id: scheduleID))
        #expect(updated.lastRunStatus == .pending)
        #expect(updated.lastRunAt == nil)
    }

    @Test func runnerPersistsFailedStatusWhenRuntimeReturnsProviderError() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let scheduleID = try scheduleStore.create(
            name: "Failure",
            cronExpression: "0 8 * * *",
            prompt: "fail"
        )
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: threads,
                messageStore: messages,
                responseText: "",
                errorToThrow: .providerNotImplemented(.appleIntelligence)
            ),
            threadStore: threads,
            scheduleStore: scheduleStore
        )

        let result = try await runner.run(scheduleID: scheduleID)

        #expect(result.status == .failed)
        #expect(result.resultRef == nil)
        #expect(result.error != nil)
        let updated = try #require(try scheduleStore.get(id: scheduleID))
        #expect(updated.lastRunAt != nil)
        #expect(updated.lastRunStatus == .failed)
        #expect(updated.lastRunResultRef == nil)
    }

    @Test func runnerRethrowsCancellationWithoutRecordingFailure() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let scheduleID = try scheduleStore.create(
            name: "Cancelled",
            cronExpression: "0 8 * * *",
            prompt: "cancel"
        )
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: threads,
                messageStore: messages,
                responseText: "",
                providerOverride: CancellingAIProvider()
            ),
            threadStore: threads,
            scheduleStore: scheduleStore
        )

        await #expect(throws: CancellationError.self) {
            _ = try await runner.run(scheduleID: scheduleID)
        }
        let updated = try #require(try scheduleStore.get(id: scheduleID))
        #expect(updated.lastRunAt == nil)
        #expect(updated.lastRunStatus == .pending)
        #expect(updated.lastRunResultRef == nil)
    }

    @Test func runnerSharesDefaultThreadForUnpinnedSchedulesWithSameKind() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let firstID = try scheduleStore.create(
            name: "Morning Brief",
            kind: .builtIn,
            cronExpression: "0 8 * * *",
            prompt: "brief"
        )
        let secondID = try scheduleStore.create(
            name: "Evening Plan",
            kind: .builtIn,
            cronExpression: "0 18 * * *",
            prompt: "plan"
        )
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: threads,
                messageStore: messages,
                responseText: "OK"
            ),
            threadStore: threads,
            scheduleStore: scheduleStore
        )

        _ = try await runner.run(scheduleID: firstID)
        _ = try await runner.run(scheduleID: secondID)

        let first = try #require(try scheduleStore.get(id: firstID))
        let second = try #require(try scheduleStore.get(id: secondID))
        let threadID = try #require(first.threadID)
        #expect(second.threadID == threadID)
        let stored = try messages.slidingWindow(threadID: threadID, last: 10)
        #expect(stored.map(\.role) == [.user, .agent, .user, .agent])
        #expect(stored.map(\.content) == ["brief", "OK", "plan", "OK"])
    }

    @Test func runnerUsesDifferentDefaultThreadsForDifferentScheduleKinds() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let builtInID = try scheduleStore.create(
            name: "Morning Brief",
            kind: .builtIn,
            cronExpression: "0 8 * * *",
            prompt: "brief"
        )
        let customID = try scheduleStore.create(
            name: "Custom",
            kind: .custom,
            cronExpression: "0 12 * * *",
            prompt: "custom"
        )
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: threads,
                messageStore: messages,
                responseText: "OK"
            ),
            threadStore: threads,
            scheduleStore: scheduleStore
        )

        _ = try await runner.run(scheduleID: builtInID)
        _ = try await runner.run(scheduleID: customID)

        let builtIn = try #require(try scheduleStore.get(id: builtInID))
        let custom = try #require(try scheduleStore.get(id: customID))
        #expect(builtIn.threadID != nil)
        #expect(custom.threadID != nil)
        #expect(builtIn.threadID != custom.threadID)
    }

    @Test func runnerUsesPinnedThreadWhenScheduleHasThreadID() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let pinnedThreadID = try threads.create(title: "Pinned")
        let scheduleID = try scheduleStore.create(
            name: "Pinned Schedule",
            kind: .projectDigest,
            cronExpression: "0 9 * * *",
            prompt: "pinned",
            threadID: pinnedThreadID
        )
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: threads,
                messageStore: messages,
                responseText: "OK"
            ),
            threadStore: threads,
            scheduleStore: scheduleStore
        )

        _ = try await runner.run(scheduleID: scheduleID)

        let updated = try #require(try scheduleStore.get(id: scheduleID))
        #expect(updated.threadID == pinnedThreadID)
        let stored = try messages.slidingWindow(threadID: pinnedThreadID, last: 10)
        #expect(stored.map(\.content) == ["pinned", "OK"])
        #expect(try threads.allActive().count == 1)
    }

    @Test func runnerDeliversTrimmedNotificationAfterSuccessfulRun() async throws {
        let context = try AgentTestSupport.makeContext()
        let threads = AgentThreadStore(context: context)
        let messages = AgentMessageStore(context: context)
        let scheduleStore = AgentScheduleStore(context: context)
        let scheduleID = try scheduleStore.create(
            name: "Morning Brief",
            cronExpression: "0 8 * * *",
            prompt: "brief"
        )
        let notificationCenter = ScheduleRecordingNotificationCenter()
        let runner = AgentScheduleRunner(
            runtime: makeRuntime(
                context: context,
                threadStore: threads,
                messageStore: messages,
                responseText: String(repeating: "b", count: 220)
            ),
            threadStore: threads,
            scheduleStore: scheduleStore,
            notificationCenter: notificationCenter
        )

        let result = try await runner.run(scheduleID: scheduleID)

        #expect(result.status == .success)
        let request = try #require(notificationCenter.snapshots().first)
        #expect(request.title == "Morning Brief")
        #expect(request.body == String(repeating: "b", count: 160))
        #expect(request.categoryIdentifier == "AGENT_BRIEF")
        #expect(request.userInfo["type"] == "agent-schedule-brief")
        #expect(request.userInfo["scheduleID"] == scheduleID.uuidString)
        #expect(request.userInfo["resultRef"] == result.resultRef?.uuidString)
    }
}

@MainActor
private func makeRuntime(
    context: ModelContext,
    threadStore: AgentThreadStore,
    messageStore: AgentMessageStore,
    responseText: String,
    errorToThrow: AIRouterError? = nil,
    providerOverride: (any AIProvider)? = nil
) -> AgentRuntime {
    let tools: [any AgentTool] = []
    let provider =
        providerOverride
        ?? FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate, .longContext],
            responseText: responseText,
            errorToThrow: errorToThrow
        )
    let builder = ContextBuilder(
        memoryStore: AgentMemoryStore(context: context),
        messageStore: messageStore,
        retriever: NoopRagRetriever(),
        tools: tools
    )
    let repository = TaskItemRepository(
        context: context,
        scheduler: RRuleScheduler(),
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let agentContext = AgentContext(
        modelContext: ModelContextRef(context),
        taskRepository: TaskItemRepositoryRef(repository),
        searchIndex: SearchIndex(),
        now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )

    return AgentRuntime(
        router: AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        ),
        threadStore: threadStore,
        messageStore: messageStore,
        contextBuilder: builder,
        dispatcher: ToolDispatcher(
            registry: ToolRegistry(tools: tools),
            modelContext: context,
            agentContext: agentContext
        )
    )
}

private struct NoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        []
    }
}

private struct CancellingAIProvider: AIProvider {
    let id: ProviderID = .appleIntelligence
    let capabilities: Set<AICapability> = [.generate, .longContext]
    let sendsDataExternally = false
    let requiresNetwork = false
    let isAvailableOnThisPlatform = true

    func generate(_ request: AIRequest) async throws -> AIResponse {
        throw CancellationError()
    }

    func transcribe(_ request: AIRequest) async throws -> AIResponse {
        throw CancellationError()
    }

    func embed(_ request: AIRequest) async throws -> AIResponse {
        throw CancellationError()
    }
}

private struct ScheduleNotificationRequestSnapshot: Sendable {
    let title: String
    let body: String
    let categoryIdentifier: String
    let userInfo: [String: String]
}

private final class ScheduleRecordingNotificationCenter: NotificationDelivering {
    private let state = OSAllocatedUnfairLock(initialState: [UNNotificationRequest]())

    func add(_ request: UNNotificationRequest) async throws {
        state.withLock { $0.append(request) }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
        state.withLock { requests in
            requests.removeAll { identifiers.contains($0.identifier) }
        }
    }

    func removeAllPendingNotificationRequests() async {
        state.withLock { $0.removeAll() }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        state.withLock { $0 }
    }

    func setNotificationCategories(_: Set<UNNotificationCategory>) async {}

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool {
        true
    }

    func notificationSettings() async -> UNNotificationSettings {
        fatalError("UNNotificationSettings has no public initializer; unused in this suite")
    }

    func snapshots() -> [ScheduleNotificationRequestSnapshot] {
        state.withLock { requests in
            requests.map { request in
                ScheduleNotificationRequestSnapshot(
                    title: request.content.title,
                    body: request.content.body,
                    categoryIdentifier: request.content.categoryIdentifier,
                    userInfo: request.content.userInfo.reduce(into: [String: String]()) { result, element in
                        if let key = element.key as? String, let value = element.value as? String {
                            result[key] = value
                        }
                    }
                )
            }
        }
    }
}
