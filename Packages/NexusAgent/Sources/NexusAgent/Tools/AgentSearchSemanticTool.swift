import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

public struct AgentSearchSemanticTool: AgentTool, RagRetriever {
    public static let maxLimit = 50

    public let name = "agent.search_semantic"
    public let description = "Hybrid FTS + vector retrieval over local tasks and agent memory."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Required non-empty search query."),
            "kinds": .array(
                items: .string(description: "Item kind raw value, for example task or agentMemory."),
                description: "Optional item kind filter."
            ),
            "projectID": .string(description: "Optional project UUID filter for task hits."),
            "scope": .string(description: "Optional memory scope filter. Defaults to global."),
            "limit": .integer(
                minimum: 1,
                maximum: AgentSearchSemanticTool.maxLimit,
                description: "Maximum hits to return. Defaults to 10."
            ),
        ],
        required: ["query"]
    )

    private let embeddingClient: any EmbeddingClient
    private let index: SqliteVecIndex
    private let ftsSearch: any FTSSearch
    private let modelContext: ModelContextRef

    @MainActor
    public init(
        embeddingClient: any EmbeddingClient = NLEmbeddingClient(),
        index: SqliteVecIndex,
        ftsSearch: any FTSSearch = NoopFTSSearch(),
        context: ModelContext
    ) {
        self.embeddingClient = embeddingClient
        self.index = index
        self.ftsSearch = ftsSearch
        self.modelContext = ModelContextRef(context)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentSearchSemanticArguments.input(from: args)
        let result = try await search(input: input)
        let output: [String: JSONValue] = [
            "hits": .array(result.hits.map(Self.jsonValue(for:))),
            "degraded": .bool(result.degraded),
            "degradationReasons": .array(result.degradationReasons.map { .string($0) }),
        ]
        return .object(output)
    }

    @MainActor
    public func retrieve(query: String, scope: String, limit: Int) async throws -> [RagHit] {
        let input = AgentSearchSemanticInput(
            query: try AgentSearchSemanticArguments.validatedQuery(query),
            kinds: nil,
            projectID: AgentSearchSemanticArguments.projectID(fromScope: scope),
            scope: scope,
            limit: try AgentSearchSemanticArguments.validatedLimit(limit)
        )
        return try await search(input: input).hits
    }

    @MainActor
    private func search(input: AgentSearchSemanticInput) async throws -> AgentSearchSemanticResult {
        let liveItems = try liveItems()
        let candidateLimit = Self.candidateLimit(for: input, liveItemCount: liveItems.ids.count)
        var rankings = [[UUID]]()
        var degradationReasons = [String]()

        do {
            let embedding = try await embeddingClient.embed(input.query)
            rankings.append(try vectorHits(query: embedding.vector, limit: candidateLimit))
        } catch {
            degradationReasons.append("vector_search_unavailable")
        }

        do {
            rankings.append(try await ftsSearch.search(query: input.query, limit: candidateLimit))
        } catch {
            degradationReasons.append("fts_search_unavailable")
        }

        let merged = ReciprocalRankFusion.merge(rankings: rankings)
        let hits = hydrate(
            merged,
            input: input,
            liveItems: liveItems
        )
        .prefix(input.limit)
        .map { $0 }
        let coverage = try embeddingCoverage(liveItemIDs: liveItems.ids)
        if coverage.isDegraded {
            degradationReasons.append("embedding_index_incomplete")
        }

        return AgentSearchSemanticResult(
            hits: hits,
            degraded: !degradationReasons.isEmpty,
            degradationReasons: Array(Set(degradationReasons)).sorted()
        )
    }

    private static func candidateLimit(for input: AgentSearchSemanticInput, liveItemCount: Int) -> Int {
        if input.hasActiveFilters {
            return max(1, liveItemCount)
        }
        return max(input.limit * 25, 250)
    }

    private func vectorHits(query: Data, limit: Int) throws -> [UUID] {
        try index.search(query: query, limit: limit).map(\.itemID)
    }

    @MainActor
    private func hydrate(
        _ hits: [ReciprocalRankFusion.Hit],
        input: AgentSearchSemanticInput,
        liveItems: LiveSearchItems
    ) -> [RagHit] {
        var hydrated = [RagHit]()
        for hit in hits {
            if input.allows(kind: .task), let task = liveItems.tasks[hit.itemID] {
                if task.deletedAt == nil && input.allowsTask(projectID: task.projectID) {
                    hydrated.append(
                        RagHit(
                            itemID: task.id,
                            kind: ItemKind.task.rawValue,
                            title: task.title,
                            snippet: (try? TaskNoteContent.plainText(for: task, in: modelContext.context)) ?? task.body,
                            score: hit.score
                        )
                    )
                    continue
                }
            }

            if input.allows(kind: .agentMemory), let memory = liveItems.memories[hit.itemID] {
                if memory.deletedAt == nil && input.allowsMemory(scope: memory.scope) {
                    hydrated.append(
                        RagHit(
                            itemID: memory.id,
                            kind: ItemKind.agentMemory.rawValue,
                            title: "\(memory.scope)/\(memory.key)",
                            snippet: memory.content,
                            score: hit.score
                        )
                    )
                }
            }
        }
        return hydrated
    }

    @MainActor
    private func liveItems() throws -> LiveSearchItems {
        let allTasks = try modelContext.context.fetch(FetchDescriptor<TaskItem>())
            .filter { $0.deletedAt == nil }
        let allMemories = try modelContext.context.fetch(FetchDescriptor<AgentMemoryEntry>())
            .filter { $0.deletedAt == nil }
        return LiveSearchItems(
            // Synced ids are not unique (CloudKit forbids @Attribute(.unique)); dedup keep-first
            // instead of trapping on a duplicate id from a sync conflict.
            tasks: Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current }),
            memories: Dictionary(allMemories.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current }),
            allLiveIDs: Set(allTasks.map(\.id)).union(allMemories.map(\.id))
        )
    }

    @MainActor
    private func embeddingCoverage(liveItemIDs: Set<UUID>) throws -> EmbeddingCoverage {
        guard !liveItemIDs.isEmpty else {
            return EmbeddingCoverage(isDegraded: false)
        }

        let embeddings = try modelContext.context.fetch(FetchDescriptor<ItemEmbedding>())
        let coveredIDs = Set(embeddings.map(\.itemID)).intersection(liveItemIDs)
        return EmbeddingCoverage(
            isDegraded: Double(coveredIDs.count) < Double(liveItemIDs.count) * 0.25
        )
    }

    private static func jsonValue(for hit: RagHit) -> JSONValue {
        .object([
            "itemID": .string(hit.itemID.uuidString),
            "kind": .string(hit.kind),
            "title": .string(hit.title),
            "snippet": .string(hit.snippet),
            "score": .double(hit.score),
        ])
    }
}

private struct AgentSearchSemanticResult {
    let hits: [RagHit]
    let degraded: Bool
    let degradationReasons: [String]
}

private struct LiveSearchItems {
    let tasks: [UUID: TaskItem]
    let memories: [UUID: AgentMemoryEntry]
    let allLiveIDs: Set<UUID>

    var ids: Set<UUID> {
        allLiveIDs
    }
}

private struct EmbeddingCoverage {
    let isDegraded: Bool
}

struct AgentSearchSemanticInput: Equatable {
    let query: String
    let kinds: Set<ItemKind>?
    let projectID: UUID?
    let scope: String?
    let limit: Int

    func allows(kind: ItemKind) -> Bool {
        kinds?.contains(kind) ?? true
    }

    func allowsTask(projectID candidate: UUID?) -> Bool {
        guard let projectID else { return true }
        return candidate == projectID
    }

    func allowsMemory(scope candidate: String) -> Bool {
        guard let scope, scope != "global" else { return true }
        return candidate == scope
    }

    var hasActiveFilters: Bool {
        kinds != nil || projectID != nil || (scope != nil && scope != "global")
    }
}

enum AgentSearchSemanticArguments {
    static func input(from args: JSONValue) throws -> AgentSearchSemanticInput {
        let object = try AgentMemoryToolArguments.object(from: args)
        return AgentSearchSemanticInput(
            query: try validatedQuery(AgentMemoryToolArguments.requiredString(object["query"], field: "query")),
            kinds: try optionalKinds(object["kinds"]),
            projectID: try optionalUUID(object["projectID"], field: "projectID"),
            scope: try AgentMemoryToolArguments.optionalString(object["scope"], field: "scope"),
            limit: try validatedLimit(
                AgentMemoryToolArguments.optionalInt(object["limit"], field: "limit") ?? 10
            )
        )
    }

    static func validatedQuery(_ query: String) throws -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("query cannot be empty")
        }
        return trimmed
    }

    static func validatedLimit(_ limit: Int) throws -> Int {
        guard (1...AgentSearchSemanticTool.maxLimit).contains(limit) else {
            throw AgentError.validation("limit must be between 1 and \(AgentSearchSemanticTool.maxLimit)")
        }
        return limit
    }

    static func projectID(fromScope scope: String) -> UUID? {
        guard scope.hasPrefix("project:") else { return nil }
        return UUID(uuidString: String(scope.dropFirst("project:".count)))
    }

    private static func optionalKinds(_ value: JSONValue?) throws -> Set<ItemKind>? {
        guard let value else { return nil }
        guard let array = value.arrayValue else {
            throw AgentError.validation("kinds must be an array of item kind strings")
        }

        var kinds = Set<ItemKind>()
        for (index, value) in array.enumerated() {
            guard let rawValue = value.stringValue else {
                throw AgentError.validation("kinds[\(index)] must be a string")
            }
            guard let kind = ItemKind(rawValue: rawValue) else {
                throw AgentError.validation("Unknown kind: \(rawValue)")
            }
            kinds.insert(kind)
        }
        return kinds
    }

    private static func optionalUUID(_ value: JSONValue?, field: String) throws -> UUID? {
        guard let value else { return nil }
        let text = try AgentMemoryToolArguments.requiredString(value, field: field)
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a UUID string")
        }
        return id
    }
}
