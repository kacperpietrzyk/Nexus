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
@Suite("WatchAgentHandler")
struct WatchAgentHandlerTests {
    @Test func replyIsTrimmedAndDeliveredAsNotification() async throws {
        let fixture = try WatchAgentFixture(responseText: String(repeating: "a", count: 220))
        let handler = fixture.makeHandler()

        let reply = try await handler.handle(prompt: "  what should I focus on?  ")

        #expect(reply.text.count == 160)
        #expect(reply.text == String(repeating: "a", count: 160))
        let thread = try #require(try fixture.threadStore.allActive().first)
        let messages = try fixture.messageStore.slidingWindow(threadID: thread.id, last: 10)
        #expect(thread.title == WatchAgentHandler.threadTitle)
        #expect(messages.first?.content == "what should I focus on?")

        let request = try #require(fixture.notificationCenter.snapshots().first)
        #expect(request.title == "Nexus")
        #expect(request.body == reply.text)
        #expect(request.categoryIdentifier == WatchAgentHandler.notificationCategoryIdentifier)
        #expect(request.threadIdentifier == WatchAgentHandler.notificationThreadIdentifier)
        #expect(request.userInfo["type"] == "watch-agent-reply")
        #expect(request.userInfo["threadID"] == thread.id.uuidString)
    }

    @Test func reusesPinnedWatchThread() async throws {
        let fixture = try WatchAgentFixture(responseText: "OK")
        let existingThreadID = try fixture.threadStore.create(title: WatchAgentHandler.threadTitle)
        let handler = fixture.makeHandler()

        _ = try await handler.handle(prompt: "first")
        _ = try await handler.handle(prompt: "second")

        let watchThreads = try fixture.threadStore
            .allActive()
            .filter { $0.title == WatchAgentHandler.threadTitle }
        #expect(watchThreads.map(\.id) == [existingThreadID])
        let messages = try fixture.messageStore.slidingWindow(threadID: existingThreadID, last: 10)
        #expect(messages.map(\.content) == ["first", "OK", "second", "OK"])
        #expect(fixture.notificationCenter.snapshots().count == 2)
    }

    @Test func emptyPromptThrowsWithoutCreatingThreadOrNotification() async throws {
        let fixture = try WatchAgentFixture(responseText: "OK")
        let handler = fixture.makeHandler()

        await #expect(throws: WatchAgentHandlerError.emptyPrompt) {
            _ = try await handler.handle(prompt: " \n\t ")
        }
        #expect(try fixture.threadStore.allActive().isEmpty)
        #expect(fixture.notificationCenter.snapshots().isEmpty)
    }

    @Test func maxIterationsThrowsWithoutNotification() async throws {
        let fixture = try WatchAgentFixture(responseText: "unused", maxIterations: 0)
        let handler = fixture.makeHandler()

        await #expect(throws: WatchAgentHandlerError.maxIterationsReached) {
            _ = try await handler.handle(prompt: "status")
        }
        #expect(fixture.notificationCenter.snapshots().isEmpty)
    }

    @Test func providerErrorThrowsWithoutNotification() async throws {
        let fixture = try WatchAgentFixture(
            responseText: "unused",
            providerError: .noProviderAvailable
        )
        let handler = fixture.makeHandler()

        await #expect(throws: WatchAgentHandlerError.providerError("noProviderAvailable")) {
            _ = try await handler.handle(prompt: "status")
        }
        #expect(fixture.notificationCenter.snapshots().isEmpty)
    }

    @Test func notificationFailureDoesNotFailReply() async throws {
        let notificationCenter = RecordingNotificationCenter(addError: NotificationFailure())
        let fixture = try WatchAgentFixture(responseText: "OK", notificationCenter: notificationCenter)
        let handler = fixture.makeHandler()

        let reply = try await handler.handle(prompt: "status")

        #expect(reply.text == "OK")
        #expect(fixture.notificationCenter.snapshots().isEmpty)
    }
}

@MainActor
private struct WatchAgentFixture {
    let context: ModelContext
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
    let runtime: AgentRuntime
    let notificationCenter: RecordingNotificationCenter

    init(
        responseText: String,
        maxIterations: Int = 5,
        providerError: AIRouterError? = nil,
        notificationCenter: RecordingNotificationCenter = RecordingNotificationCenter()
    ) throws {
        context = try AgentTestSupport.makeContext()
        threadStore = AgentThreadStore(context: context)
        messageStore = AgentMessageStore(context: context)
        self.notificationCenter = notificationCenter
        runtime = Self.makeRuntime(
            stores: RuntimeStores(
                context: context,
                threadStore: threadStore,
                messageStore: messageStore
            ),
            responseText: responseText,
            maxIterations: maxIterations,
            providerError: providerError
        )
    }

    func makeHandler() -> WatchAgentHandler {
        WatchAgentHandler(
            runtime: runtime,
            threadStore: threadStore,
            notificationCenter: notificationCenter
        )
    }

    private static func makeRuntime(
        stores: RuntimeStores,
        responseText: String,
        maxIterations: Int,
        providerError: AIRouterError?
    ) -> AgentRuntime {
        let tools: [any AgentTool] = []
        let builder = ContextBuilder(
            memoryStore: AgentMemoryStore(context: stores.context),
            messageStore: stores.messageStore,
            retriever: NoopRagRetriever(),
            tools: tools
        )
        let repository = TaskItemRepository(
            context: stores.context,
            scheduler: RRuleScheduler(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let agentContext = AgentContext(
            modelContext: ModelContextRef(stores.context),
            taskRepository: TaskItemRepositoryRef(repository),
            searchIndex: SearchIndex(),
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        return AgentRuntime(
            router: AIRouter(
                providers: [
                    FakeAIProvider(
                        id: .appleIntelligence,
                        capabilities: [.generate, .longContext],
                        responseText: responseText,
                        errorToThrow: providerError
                    )
                ],
                consent: InMemoryConsentStore(),
                quota: InMemoryQuotaTracker(),
                secrets: InMemorySecretStore()
            ),
            threadStore: stores.threadStore,
            messageStore: stores.messageStore,
            contextBuilder: builder,
            dispatcher: ToolDispatcher(
                registry: ToolRegistry(tools: tools),
                modelContext: stores.context,
                agentContext: agentContext
            ),
            maxIterations: maxIterations
        )
    }
}

private struct RuntimeStores {
    let context: ModelContext
    let threadStore: AgentThreadStore
    let messageStore: AgentMessageStore
}

private struct NotificationFailure: Error {}

private struct NoopRagRetriever: RagRetriever {
    func retrieve(query _: String, scope _: String, limit _: Int) async throws -> [RagHit] {
        []
    }
}

private struct NotificationRequestSnapshot: Sendable {
    let title: String
    let body: String
    let categoryIdentifier: String
    let threadIdentifier: String
    let userInfo: [String: String]
}

private final class RecordingNotificationCenter: NotificationDelivering {
    private let state = OSAllocatedUnfairLock(initialState: [UNNotificationRequest]())
    private let addError: (any Error)?

    init(addError: (any Error)? = nil) {
        self.addError = addError
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let addError {
            throw addError
        }
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

    func snapshots() -> [NotificationRequestSnapshot] {
        state.withLock { requests in
            requests.map { request in
                NotificationRequestSnapshot(
                    title: request.content.title,
                    body: request.content.body,
                    categoryIdentifier: request.content.categoryIdentifier,
                    threadIdentifier: request.content.threadIdentifier,
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
