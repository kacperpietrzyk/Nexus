import CryptoKit
import Foundation
import NexusAgentTools
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

/// Body-resolution guards for the MP-4.1 slice-2 Settings section-body
/// accent/Semantic burn-down. Tokens are already achromatic post-MP-0, so
/// the regression seam is body resolution along the retuned paths: these
/// pin `AgentIndexingSection` (ProgressView `.tint`), `AgentMemoryEditorSection`
/// (destructive `trash`), `AgentAuditSection` ("Undone" status), and
/// `AgentScheduleEditorSection` (validation-error text — its `validationError`
/// branch lives in a `private` nested view behind `@State`, so per the
/// slice-1 adjudication the reachable seam is the parent section + content
/// body; the per-site source audit comment names the burn). View-introspection
/// tooling is intentionally not used (same constraint adjudicated in slice 1).
@MainActor
@Suite struct AgentSettingsSectionsBodyResolutionTests {
    @Test func indexingSection_resolvesBody() throws {
        let context = try Self.makeSettingsContext()
        let view = AgentIndexingSection(context: context)
        _ = view.body
    }

    @Test func memoryEditorSection_resolvesBody() throws {
        let context = try Self.makeSettingsContext()
        let view = AgentMemoryEditorSection(context: context)
        _ = view.body
    }

    @Test func auditSection_resolvesBody() throws {
        let context = try Self.makeSettingsContext()
        let view = AgentAuditSection(context: context)
        _ = view.body
    }

    @Test func scheduleEditorSection_resolvesBodyWithStore() throws {
        let context = try Self.makeSettingsContext(withScheduleStore: true)
        let view = AgentScheduleEditorSection(context: context)
        _ = view.body
    }

    @Test func scheduleEditorSection_resolvesBodyWithoutStore() throws {
        let context = try Self.makeSettingsContext(withScheduleStore: false)
        let view = AgentScheduleEditorSection(context: context)
        _ = view.body
    }

    private static func makeSettingsContext(
        withScheduleStore: Bool = true
    ) throws -> AgentSettingsContext {
        let schema = Schema([
            AgentAuditLog.self,
            AgentMemoryEntry.self,
            AgentMessage.self,
            AgentSchedule.self,
            AgentThread.self,
            DebugItem.self,
            ItemEmbedding.self,
            Link.self,
            QuotaLog.self,
            TaskItem.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let dispatcher = EmbeddingDispatcher(
            embeddingClient: StubEmbeddingClient(),
            index: try SqliteVecIndex.inMemory(dimension: 4),
            context: context,
            debounce: .milliseconds(0)
        )
        let backfill = BackfillEmbeddingsJob(context: context, dispatcher: dispatcher)

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
        let registry = ToolRegistry(tools: [])
        let toolDispatcher = ToolDispatcher(
            registry: registry,
            modelContext: context,
            agentContext: agentContext
        )
        let undoCoordinator = AgentUndoCoordinator(
            registry: registry,
            dispatcher: toolDispatcher,
            context: context
        )

        return AgentSettingsContext(
            memoryStore: AgentMemoryStore(context: context),
            scheduleStore: withScheduleStore ? AgentScheduleStore(context: context) : nil,
            auditContext: context,
            backfillJob: backfill,
            undoCoordinator: undoCoordinator
        )
    }
}

private final class StubEmbeddingClient: EmbeddingClient, @unchecked Sendable {
    func embed(_ text: String) async throws -> NLEmbeddingResult {
        let seed = Float(abs(text.hashValue % 1_000)) / 1_000
        let floats: [Float] = [seed, seed + 0.01, seed + 0.02, seed + 0.03]
        let vector = floats.withUnsafeBufferPointer { Data(buffer: $0) }
        let digest = SHA256.hash(data: Data(text.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return NLEmbeddingResult(
            vector: vector,
            detectedLanguage: "test",
            textHash: hash,
            dimension: 4
        )
    }
}
