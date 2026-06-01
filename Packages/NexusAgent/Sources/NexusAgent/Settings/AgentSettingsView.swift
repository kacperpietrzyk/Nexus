import NexusAI
import NexusUI
import SwiftData
import SwiftUI

/// Schedule-store seam for Settings surfaces.
public protocol AgentScheduleStoreProviding {
    @discardableResult
    func save(_ mutation: AgentScheduleStoreMutation, id: UUID?) throws -> UUID

    func allActive() throws -> [AgentSchedule]
    func setEnabled(_ enabled: Bool, id: UUID) throws
}

public struct AgentSettingsContext {
    public let memoryStore: AgentMemoryStore
    public let scheduleStore: AgentScheduleStoreProviding?
    public let auditContext: ModelContext
    public let backfillJob: BackfillEmbeddingsJob
    public let undoCoordinator: AgentUndoCoordinator
    public let aiLiveData: AISettingsLiveData?

    public init(
        memoryStore: AgentMemoryStore,
        scheduleStore: AgentScheduleStoreProviding? = nil,
        auditContext: ModelContext,
        backfillJob: BackfillEmbeddingsJob,
        undoCoordinator: AgentUndoCoordinator,
        aiLiveData: AISettingsLiveData? = nil
    ) {
        self.memoryStore = memoryStore
        self.scheduleStore = scheduleStore
        self.auditContext = auditContext
        self.backfillJob = backfillJob
        self.undoCoordinator = undoCoordinator
        self.aiLiveData = aiLiveData
    }
}

public struct AgentSettingsView: View {
    public enum Section: String, CaseIterable, Sendable {
        // swiftlint:disable:next inclusive_language
        case masterSwitch
        case providerRouting
        case schedulesEditor
        case indexing
        case memoryEditor
        case audit
        case devHub
    }

    nonisolated public static let sectionOrder: [Section] = [
        .masterSwitch,
        .providerRouting,
        .schedulesEditor,
        .indexing,
        .memoryEditor,
        .audit,
        .devHub,
    ]

    private let context: AgentSettingsContext

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        NexusSettingsDetailContainer(title: "Agent") {
            VStack(alignment: .leading, spacing: NexusSpacing.s7) {
                ForEach(Self.sectionOrder, id: \.self) { section in
                    sectionBody(section)
                }
            }
        }
    }

    @ViewBuilder
    private func sectionBody(_ section: Section) -> some View {
        switch section {
        case .masterSwitch:
            AgentMasterSwitchSection(context: context)
        case .providerRouting:
            AgentProviderRoutingSection(context: context)
        case .schedulesEditor:
            AgentScheduleEditorSection(context: context)
        case .indexing:
            AgentIndexingSection(context: context)
        case .memoryEditor:
            AgentMemoryEditorSection(context: context)
        case .audit:
            AgentAuditSection(context: context)
        case .devHub:
            AgentDevHubSection(context: context)
        }
    }
}
