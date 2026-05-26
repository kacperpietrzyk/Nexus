import Foundation
import NexusAgentTools
import NexusCore
import Testing

@testable import NexusAgent

@Suite(.serialized)
struct ContextBuilderTests {
    @Test func builderIncludesMemoryAndWindow() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let memStore = AgentMemoryStore(context: ctx)
        _ = try memStore.upsert(
            scope: "global",
            key: "prefers-pl",
            content: "user prefers Polish"
        )
        let threads = AgentThreadStore(context: ctx)
        let msgs = AgentMessageStore(context: ctx)
        let threadID = try threads.create(title: "t")
        let timestamp = Date(timeIntervalSince1970: 1_777_200_000)
        let toolCallJSON = Data(#"{"name":"tasks.list"}"#.utf8)
        let message = AgentMessage(
            threadID: threadID,
            createdAt: timestamp,
            role: .user,
            content: "co dziś najważniejsze?",
            toolCallJSON: toolCallJSON,
            attachments: ["file://capture.txt"],
            tokensIn: 12,
            tokensOut: 34,
            providerID: "test-provider",
            redactedContent: true
        )
        ctx.insert(message)
        try ctx.save()

        let builder = ContextBuilder(
            memoryStore: memStore,
            messageStore: msgs,
            retriever: NoopRagRetriever(),
            tools: []
        )
        let window = try await builder.build(
            threadID: threadID,
            scope: "global",
            userPrompt: "co dziś najważniejsze?"
        )

        #expect(window.systemPrompt.contains("Nexus Agent"))
        #expect(window.memorySection.contains("user prefers Polish"))
        #expect(window.recentMessages.count == 1)
        let snapshot = try #require(window.recentMessages.first)
        #expect(snapshot.id == message.id)
        #expect(snapshot.threadID == threadID)
        #expect(snapshot.createdAt == timestamp)
        #expect(snapshot.role == .user)
        #expect(snapshot.content == "co dziś najważniejsze?")
        #expect(snapshot.toolCallJSON == toolCallJSON)
        #expect(snapshot.attachments == ["file://capture.txt"])
        #expect(snapshot.tokensIn == 12)
        #expect(snapshot.tokensOut == 34)
        #expect(snapshot.providerID == "test-provider")
        #expect(snapshot.redactedContent)
        #expect(window.retrievedHits.isEmpty)
        #expect(window.toolDefinitionsJSON == Data("[]".utf8))
        #expect(window.estimatedTokens > 0)
        #expect(!window.shouldEscalate)
    }

    @Test func builderLimitsMemoryAndSlidingWindow() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let memStore = AgentMemoryStore(context: ctx)
        let threads = AgentThreadStore(context: ctx)
        let msgs = AgentMessageStore(context: ctx)
        let threadID = try threads.create(title: "t")

        for index in 0..<8 {
            _ = try memStore.upsert(
                scope: "global",
                key: "k\(index)",
                content: "memory \(index)",
                now: Date(timeIntervalSince1970: TimeInterval(index))
            )
            _ = try msgs.append(
                threadID: threadID,
                role: .user,
                content: "message \(index)",
                now: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let builder = ContextBuilder(
            memoryStore: memStore,
            messageStore: msgs,
            retriever: NoopRagRetriever(),
            tools: []
        )
        let window = try await builder.build(
            threadID: threadID,
            scope: "global",
            userPrompt: "latest",
            slidingWindowSize: 3,
            memoryLimit: 5
        )

        #expect(window.memorySection.contains("memory 7"))
        #expect(window.memorySection.contains("memory 3"))
        #expect(!window.memorySection.contains("memory 2"))
        #expect(window.recentMessages.map(\.content) == ["message 5", "message 6", "message 7"])
    }

    @Test func builderEscalatesOnTokenOverflow() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let memStore = AgentMemoryStore(context: ctx)
        for index in 0..<60 {
            _ = try memStore.upsert(
                scope: "global",
                key: "k\(index)",
                content: String(repeating: "x", count: 200),
                now: Date(timeIntervalSince1970: TimeInterval(index))
            )
        }

        let builder = ContextBuilder(
            memoryStore: memStore,
            messageStore: AgentMessageStore(context: ctx),
            retriever: NoopRagRetriever(),
            tools: [],
            appleFMTokenLimit: 100
        )
        let window = try await builder.build(
            threadID: UUID(),
            scope: "global",
            userPrompt: "x"
        )

        #expect(window.shouldEscalate)
    }

    @Test func builderEscalatesForZeroOrNegativeLimitsWhenNonEmpty() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let builder = ContextBuilder(
            memoryStore: AgentMemoryStore(context: ctx),
            messageStore: AgentMessageStore(context: ctx),
            retriever: NoopRagRetriever(),
            tools: [],
            appleFMTokenLimit: 0
        )

        let zero = try await builder.build(threadID: UUID(), scope: "global", userPrompt: "")
        #expect(zero.shouldEscalate)

        let negative = ContextBuilder(
            memoryStore: AgentMemoryStore(context: ctx),
            messageStore: AgentMessageStore(context: ctx),
            retriever: NoopRagRetriever(),
            tools: [],
            appleFMTokenLimit: -1
        )
        let negativeWindow = try await negative.build(
            threadID: UUID(),
            scope: "global",
            userPrompt: ""
        )
        #expect(negativeWindow.shouldEscalate)
    }

    @Test func builderIncludesRetrievedHits() async throws {
        let hit = RagHit(
            itemID: UUID(),
            kind: "task",
            title: "Plan",
            snippet: "Retrieved context snippet",
            score: 0.9
        )
        let retriever = StubRagRetriever(hits: [hit])
        let ctx = try AgentTestSupport.makeContext()
        let builder = ContextBuilder(
            memoryStore: AgentMemoryStore(context: ctx),
            messageStore: AgentMessageStore(context: ctx),
            retriever: retriever,
            tools: []
        )

        let window = try await builder.build(
            threadID: UUID(),
            scope: "global",
            userPrompt: "find context",
            ragLimit: 1
        )

        #expect(window.retrievedHits == [hit])
        let request = await retriever.request
        #expect(request?.query == "find context")
        #expect(request?.scope == "global")
        #expect(request?.limit == 1)
    }

    @Test func builderToolDefinitionsIncludeStableInputSchemas() async throws {
        let ctx = try AgentTestSupport.makeContext()
        let builder = ContextBuilder(
            memoryStore: AgentMemoryStore(context: ctx),
            messageStore: AgentMessageStore(context: ctx),
            retriever: NoopRagRetriever(),
            tools: [
                StubTool(name: "z.tool"),
                StubTool(
                    name: "a.tool",
                    inputSchema: .object(
                        properties: ["text": .string(description: "Input text")],
                        required: ["text"]
                    )
                ),
            ]
        )

        let window = try await builder.build(
            threadID: UUID(),
            scope: "global",
            userPrompt: "tools"
        )
        let tools = try #require(
            JSONSerialization.jsonObject(with: window.toolDefinitionsJSON) as? [[String: Any]]
        )

        #expect(tools.map { $0["name"] as? String } == ["a.tool", "z.tool"])
        let first = try #require(tools.first)
        #expect(first["description"] as? String == "stub a.tool")
        let inputSchema = try #require(first["input_schema"] as? [String: Any])
        #expect(inputSchema["type"] as? String == "object")
        let properties = try #require(inputSchema["properties"] as? [String: Any])
        #expect(properties["text"] != nil)
        #expect(String(data: window.toolDefinitionsJSON, encoding: .utf8)?.contains("input_schema") == true)
    }
}

private struct NoopRagRetriever: RagRetriever {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        []
    }
}

private actor StubRagRetriever: RagRetriever {
    private let hits: [RagHit]
    private(set) var request: RagRequest?

    init(hits: [RagHit]) {
        self.hits = hits
    }

    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        request = RagRequest(query: query, scope: scope, limit: limit)
        return hits
    }
}

private struct RagRequest: Sendable {
    let query: String
    let scope: String
    let limit: Int
}

private struct StubTool: AgentTool {
    let name: String
    let description: String
    let inputSchema: JSONSchema

    init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema = .object(properties: [:], required: [])
    ) {
        self.name = name
        self.description = description ?? "stub \(name)"
        self.inputSchema = inputSchema
    }

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        args
    }
}
