import Foundation
import Testing

@testable import NexusAgent

@MainActor
@Suite struct PendingInsightStoreTests {
    private func proposal() -> Proposal { Proposal(rationale: "x", mutations: [], previews: []) }

    @Test func addListResolve() {
        let store = PendingInsightStore()
        store.add(kind: "overload", dedupeKey: "overload:d1", proposal: proposal())
        #expect(store.pending.count == 1)
        let id = store.pending[0].id
        store.resolve(id: id)
        #expect(store.pending.isEmpty)
    }

    @Test func duplicateDedupeKeyKeepsOne() {
        let store = PendingInsightStore()
        store.add(kind: "overload", dedupeKey: "k", proposal: proposal())
        store.add(kind: "overload", dedupeKey: "k", proposal: proposal())
        #expect(store.pending.count == 1)
    }
}
