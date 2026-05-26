import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

public enum AgentUndoError: Error, Equatable, Sendable {
    case auditLogNotFound(UUID)
    case alreadyUndone(UUID)
    case noInverseRecorded(UUID)
    case undoInProgress(UUID)
}

@MainActor
public final class AgentUndoCoordinator {
    private let dispatcher: ToolDispatcher
    private let modelContext: ModelContext
    private let decoder: JSONDecoder
    private var undoInFlightIDs: Set<UUID> = []

    public init(
        dispatcher: ToolDispatcher,
        modelContext: ModelContext,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.dispatcher = dispatcher
        self.modelContext = modelContext
        self.decoder = decoder
    }

    public convenience init(
        registry _: ToolRegistry,
        dispatcher: ToolDispatcher,
        context: ModelContext,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.init(dispatcher: dispatcher, modelContext: context, decoder: decoder)
    }

    public func undo(auditLogID: UUID, now: Date = .now) async throws {
        let entry = try auditLog(for: auditLogID)
        guard entry.undoneAt == nil else {
            throw AgentUndoError.alreadyUndone(auditLogID)
        }
        guard let inverseData = entry.inverseAction else {
            throw AgentUndoError.noInverseRecorded(auditLogID)
        }
        guard !undoInFlightIDs.contains(auditLogID) else {
            throw AgentUndoError.undoInProgress(auditLogID)
        }

        undoInFlightIDs.insert(auditLogID)
        defer { undoInFlightIDs.remove(auditLogID) }

        let inverse = try decoder.decode(InverseAction.self, from: inverseData)
        let inverseInput = try decoder.decode(JSONValue.self, from: inverse.inputJSON)
        let result = try await dispatcher.dispatch(
            toolName: inverse.toolName,
            input: inverseInput,
            threadID: entry.threadID,
            now: now
        )

        let inverseEntry = try auditLog(for: result.auditLogID)
        inverseEntry.undoneAt = now
        entry.undoneAt = now
        try modelContext.save()
    }

    public func undoAll(threadID: UUID, now: Date = .now) async throws {
        var descriptor = FetchDescriptor<AgentAuditLog>(
            predicate: #Predicate {
                $0.threadID == threadID && $0.undoneAt == nil && $0.inverseAction != nil
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.includePendingChanges = true

        let entryIDs = try modelContext.fetch(descriptor).map(\.id)
        for entryID in entryIDs {
            try await undo(auditLogID: entryID, now: now)
        }
    }

    private func auditLog(for id: UUID) throws -> AgentAuditLog {
        var descriptor = FetchDescriptor<AgentAuditLog>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = true

        guard let entry = try modelContext.fetch(descriptor).first else {
            throw AgentUndoError.auditLogNotFound(id)
        }
        return entry
    }
}
