// Packages/NexusAgent/Tests/NexusAgentTests/PendingInsightStorePersistenceTests.swift
import Foundation
import SwiftData
import Testing
import NexusCore
@testable import NexusAgent

@MainActor
@Suite struct PendingInsightStorePersistenceTests {
    private func repo() throws -> AgentInsightRepository {
        let c = try ModelContainer(for: Schema([AgentInsightRecord.self]),
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return AgentInsightRepository(context: ModelContext(c))
    }
    private func proposal() -> Proposal {
        Proposal(rationale: "r", mutations: [], previews: [ProposalPreview(summary: "s")])
    }

    @Test func addPersistsAndSurvivesReinit() throws {
        let repository = try repo()
        let store1 = PendingInsightStore(repository: repository)
        store1.add(kind: "day_plan", dedupeKey: "k1", proposal: proposal())
        #expect(store1.pending.count == 1)
        // A fresh store over the same repository rehydrates from disk.
        let store2 = PendingInsightStore(repository: repository)
        #expect(store2.pending.count == 1)
        #expect(store2.pending.first?.dedupeKey == "k1")
    }

    @Test func resolveRemovesPersistently() throws {
        let repository = try repo()
        let store = PendingInsightStore(repository: repository)
        store.add(kind: "x", dedupeKey: "k", proposal: proposal())
        let id = try #require(store.pending.first?.id)
        store.resolve(id: id)
        #expect(store.pending.isEmpty)
        #expect(PendingInsightStore(repository: repository).pending.isEmpty)
    }
}
