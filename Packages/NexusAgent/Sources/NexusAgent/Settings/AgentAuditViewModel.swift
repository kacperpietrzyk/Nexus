import Combine
import Foundation
import SwiftData

@MainActor
public final class AgentAuditViewModel: ObservableObject {
    @Published public private(set) var entries: [AgentAuditLog] = []
    @Published public private(set) var isUndoing = false

    private let context: ModelContext
    private let undoCoordinator: AgentUndoCoordinator

    public init(context: ModelContext, undoCoordinator: AgentUndoCoordinator) {
        self.context = context
        self.undoCoordinator = undoCoordinator
        reload()
    }

    public func reload() {
        var descriptor = FetchDescriptor<AgentAuditLog>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        descriptor.includePendingChanges = true

        do {
            entries = try context.fetch(descriptor)
        } catch {
            entries = []
        }
    }

    public func undo(id: UUID) async {
        isUndoing = true
        defer {
            isUndoing = false
            reload()
        }

        try? await undoCoordinator.undo(auditLogID: id)
    }

    public func undoThread(_ threadID: UUID) async {
        isUndoing = true
        defer {
            isUndoing = false
            reload()
        }

        try? await undoCoordinator.undoAll(threadID: threadID)
    }
}
