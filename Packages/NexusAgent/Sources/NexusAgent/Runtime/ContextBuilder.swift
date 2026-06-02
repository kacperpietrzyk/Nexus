import Foundation
import NexusAgentTools

public protocol RagRetriever: Sendable {
    func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit]
}

public struct RagHit: Sendable, Equatable {
    public let itemID: UUID
    public let kind: String
    public let title: String
    public let snippet: String
    public let score: Double

    public init(
        itemID: UUID,
        kind: String,
        title: String,
        snippet: String,
        score: Double
    ) {
        self.itemID = itemID
        self.kind = kind
        self.title = title
        self.snippet = snippet
        self.score = score
    }
}

public struct AgentMessageSnapshot: Sendable, Equatable {
    public let id: UUID
    public let threadID: UUID
    public let createdAt: Date
    public let role: AgentMessageRole
    public let content: String
    public let toolCallJSON: Data?
    public let attachments: [String]
    public let tokensIn: Int
    public let tokensOut: Int
    public let providerID: String
    public let redactedContent: Bool

    public init(
        id: UUID,
        threadID: UUID,
        createdAt: Date,
        role: AgentMessageRole,
        content: String,
        toolCallJSON: Data?,
        attachments: [String],
        tokensIn: Int,
        tokensOut: Int,
        providerID: String,
        redactedContent: Bool
    ) {
        self.id = id
        self.threadID = threadID
        self.createdAt = createdAt
        self.role = role
        self.content = content
        self.toolCallJSON = toolCallJSON
        self.attachments = attachments
        self.tokensIn = tokensIn
        self.tokensOut = tokensOut
        self.providerID = providerID
        self.redactedContent = redactedContent
    }

    public init(message: AgentMessage) {
        self.init(
            id: message.id,
            threadID: message.threadID,
            createdAt: message.createdAt,
            role: message.role,
            content: message.content,
            toolCallJSON: message.toolCallJSON,
            attachments: message.attachments,
            tokensIn: message.tokensIn,
            tokensOut: message.tokensOut,
            providerID: message.providerID,
            redactedContent: message.redactedContent
        )
    }
}

public struct AgentContextWindow: Sendable {
    public let systemPrompt: String
    public let memorySection: String
    public let recentMessages: [AgentMessageSnapshot]
    public let retrievedHits: [RagHit]
    public let toolDefinitionsJSON: Data
    public let estimatedTokens: Int
    public let shouldEscalate: Bool

    public init(
        systemPrompt: String,
        memorySection: String,
        recentMessages: [AgentMessageSnapshot],
        retrievedHits: [RagHit],
        toolDefinitionsJSON: Data,
        estimatedTokens: Int,
        shouldEscalate: Bool
    ) {
        self.systemPrompt = systemPrompt
        self.memorySection = memorySection
        self.recentMessages = recentMessages
        self.retrievedHits = retrievedHits
        self.toolDefinitionsJSON = toolDefinitionsJSON
        self.estimatedTokens = estimatedTokens
        self.shouldEscalate = shouldEscalate
    }
}

public final class ContextBuilder {
    private let memoryStore: AgentMemoryStore
    private let messageStore: AgentMessageStore
    private let retriever: RagRetriever
    private let tools: [AgentTool]
    private let appleFMTokenLimit: Int

    public init(
        memoryStore: AgentMemoryStore,
        messageStore: AgentMessageStore,
        retriever: RagRetriever,
        tools: [AgentTool],
        appleFMTokenLimit: Int = 7_000
    ) {
        self.memoryStore = memoryStore
        self.messageStore = messageStore
        self.retriever = retriever
        self.tools = tools
        self.appleFMTokenLimit = appleFMTokenLimit
    }

    public func build(
        threadID: UUID,
        scope: String,
        userPrompt: String,
        slidingWindowSize: Int = 10,
        memoryLimit: Int = 5,
        ragLimit: Int = 5
    ) async throws -> AgentContextWindow {
        let systemPrompt = Self.systemPrompt
        let memorySection: String
        do {
            let memories = try memoryStore.recent(scope: scope, limit: memoryLimit)
            memorySection =
                memories
                .map { "- [\($0.scope)/\($0.key)] \($0.content)" }
                .joined(separator: "\n")
        }

        let messageSnapshots: [AgentMessageSnapshot]
        let messageTokenEstimate: Int
        do {
            let recentMessages = try messageStore.slidingWindow(
                threadID: threadID,
                last: slidingWindowSize
            )
            messageSnapshots = recentMessages.map(AgentMessageSnapshot.init(message:))
            messageTokenEstimate =
                messageSnapshots
                .map { TokenBudget.estimate($0.content) }
                .reduce(0, +)
        }

        let retrievedHits = try await retriever.retrieve(
            query: userPrompt,
            scope: scope,
            limit: ragLimit
        )
        let toolDefs = Self.toolDefinitionsJSON(tools: tools)
        let toolDefsText = String(data: toolDefs, encoding: .utf8) ?? ""

        let estimatedTokens =
            TokenBudget.estimate(systemPrompt)
            + TokenBudget.estimate(memorySection)
            + messageTokenEstimate
            + retrievedHits.map { TokenBudget.estimate($0.snippet) }.reduce(0, +)
            + TokenBudget.estimate(userPrompt)
            + TokenBudget.estimate(toolDefsText)

        return AgentContextWindow(
            systemPrompt: systemPrompt,
            memorySection: memorySection,
            recentMessages: messageSnapshots,
            retrievedHits: retrievedHits,
            toolDefinitionsJSON: toolDefs,
            estimatedTokens: estimatedTokens,
            shouldEscalate: estimatedTokens > appleFMTokenLimit
        )
    }

    private static let systemPrompt = """
        You are Nexus Agent, the personal copilot inside Nexus. You operate over
        the user's local Tasks plus their agent memory.
        Tools you call MUST come from the provided tool definitions. For any
        mutating tool, the dispatcher will record the call in AgentAuditLog and
        capture an inverseAction for undo. Reply in the user's language; default
        to English if uncertain.
        """

    private static func toolDefinitionsJSON(tools: [AgentTool]) -> Data {
        let entries =
            tools
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { tool in
                ToolEntryDTO(
                    name: tool.name,
                    description: tool.description,
                    inputSchema: tool.inputSchema
                )
            }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(entries)) ?? Data("[]".utf8)
    }
}
