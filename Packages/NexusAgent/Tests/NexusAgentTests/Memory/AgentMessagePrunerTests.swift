import Foundation
import SwiftData
import Testing

@testable import NexusAgent

@Suite(.serialized)
struct AgentMessagePrunerTests {
    @Test func prunerRedactsMessagesOlderThan30Days() throws {
        let container = try ModelContainer(
            for: Schema([AgentThread.self, AgentMessage.self]),
            configurations: [.init(isStoredInMemoryOnly: true)]
        )
        let ctx = ModelContext(container)
        let threadID = UUID()
        ctx.insert(AgentThread(id: threadID))
        let oldDate = Date.now.addingTimeInterval(-40 * 86_400)
        let recentDate = Date.now.addingTimeInterval(-5 * 86_400)
        let firstLine = String(repeating: "old content ", count: 20)
        let secondLine = "second line should not survive redaction"
        let oldContent = "\(firstLine)\n\(secondLine)"
        ctx.insert(
            AgentMessage(
                threadID: threadID,
                createdAt: oldDate,
                role: .user,
                content: oldContent
            )
        )
        let recentContent = "fresh content"
        ctx.insert(
            AgentMessage(
                threadID: threadID,
                createdAt: recentDate,
                role: .user,
                content: recentContent
            )
        )
        try ctx.save()

        let summary = try AgentMessagePruner().prune(context: ctx, now: .now, retainDays: 30)
        #expect(summary.redacted == 1)
        #expect(summary.preserved == 1)

        let messages = try ctx.fetch(
            FetchDescriptor<AgentMessage>(sortBy: [SortDescriptor(\.createdAt)])
        )
        #expect(messages.count == 2)
        let oldMessage = try #require(messages.first)
        let recentMessage = try #require(messages.last)

        #expect(oldMessage.redactedContent)
        #expect(oldMessage.content == String(firstLine.prefix(160)))
        #expect(!oldMessage.content.contains(secondLine))
        #expect(!recentMessage.redactedContent)
        #expect(recentMessage.content == recentContent)
    }

    @Test func prunerPersistsRedactionToOnDiskStore() throws {
        let storeURL = tempStoreURL(prefix: "agent-message-pruner")
        defer { cleanupStore(at: storeURL) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldDate = now.addingTimeInterval(-40 * 86_400)
        let firstLine = String(repeating: "persistent old content ", count: 12)
        let secondLine = "persistent second line"
        let messageID = UUID()

        let container = try makeAgentMessageContainer(storeURL: storeURL)
        let context = ModelContext(container)
        context.insert(
            AgentMessage(
                id: messageID,
                threadID: UUID(),
                createdAt: oldDate,
                role: .user,
                content: "\(firstLine)\n\(secondLine)"
            )
        )
        try context.save()

        let summary = try AgentMessagePruner().prune(context: context, now: now, retainDays: 30)
        #expect(summary.redacted == 1)
        #expect(summary.preserved == 0)

        let verificationContext = ModelContext(container)
        let storedMessages = try verificationContext.fetch(FetchDescriptor<AgentMessage>())
        let storedMessage = try #require(storedMessages.first { $0.id == messageID })

        #expect(storedMessage.redactedContent)
        #expect(storedMessage.content == String(firstLine.prefix(160)))
        #expect(!storedMessage.content.contains(secondLine))
    }

    @Test func prunerHandlesAlreadyRedactedEmptyAndExactCutoffMessages() throws {
        let container = try ModelContainer(
            for: Schema([AgentMessage.self]),
            configurations: [.init(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let cutoff = now.addingTimeInterval(-30 * 86_400)
        let oldDate = cutoff.addingTimeInterval(-1)
        let alreadyRedactedID = UUID()
        let emptyID = UUID()
        let exactCutoffID = UUID()
        let alreadyRedactedContent = "already summarized"
        let exactCutoffContent = "exact cutoff content"

        context.insert(
            AgentMessage(
                id: alreadyRedactedID,
                threadID: UUID(),
                createdAt: oldDate,
                role: .agent,
                content: alreadyRedactedContent,
                redactedContent: true
            )
        )
        context.insert(
            AgentMessage(
                id: emptyID,
                threadID: UUID(),
                createdAt: oldDate,
                role: .user,
                content: ""
            )
        )
        context.insert(
            AgentMessage(
                id: exactCutoffID,
                threadID: UUID(),
                createdAt: cutoff,
                role: .user,
                content: exactCutoffContent
            )
        )
        try context.save()

        let summary = try AgentMessagePruner().prune(context: context, now: now, retainDays: 30)
        #expect(summary.redacted == 1)
        #expect(summary.preserved == 1)

        let messages = try context.fetch(FetchDescriptor<AgentMessage>())
        let alreadyRedacted = try #require(messages.first { $0.id == alreadyRedactedID })
        let empty = try #require(messages.first { $0.id == emptyID })
        let exactCutoff = try #require(messages.first { $0.id == exactCutoffID })

        #expect(alreadyRedacted.redactedContent)
        #expect(alreadyRedacted.content == alreadyRedactedContent)
        #expect(empty.redactedContent)
        #expect(empty.content.isEmpty)
        #expect(!exactCutoff.redactedContent)
        #expect(exactCutoff.content == exactCutoffContent)
    }

    @Test func prunerSkipsWhenWithinCooldown() throws {
        let suiteName = "test-pruner-skip-\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            Date.now.addingTimeInterval(-3600),
            forKey: "AgentMessagePruner.lastRunAt"
        )
        let container = try ModelContainer(
            for: Schema([AgentMessage.self]),
            configurations: [.init(isStoredInMemoryOnly: true)]
        )
        let outcome = try AgentMessagePruner().runIfNeeded(
            context: ModelContext(container),
            defaults: defaults,
            now: .now,
            cadence: 86_400,
            retainDays: 30
        )
        #expect(outcome == .skipped)
    }
}

private func makeAgentMessageContainer(storeURL: URL) throws -> ModelContainer {
    let schema = Schema([AgentMessage.self])
    let config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [config])
}

private func tempStoreURL(prefix: String) -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(prefix)-\(UUID().uuidString).store")
}

private func cleanupStore(at url: URL) {
    let fileManager = FileManager.default
    try? fileManager.removeItem(at: url)
    try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    try? fileManager.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
}
