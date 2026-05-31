import Foundation
import Testing

@testable import NexusCore

@Suite("OrderIndex.midpoint")
struct OrderIndexTests {

    @Test("inserting between two values returns the midpoint")
    func midpointBetween() {
        #expect(OrderIndex.midpoint(prev: 1.0, next: 2.0) == 1.5)
        #expect(OrderIndex.midpoint(prev: 0.0, next: 100.0) == 50.0)
    }

    @Test("inserting at the head with no prev returns next - 1")
    func headInsert() {
        #expect(OrderIndex.midpoint(prev: nil, next: 5.0) == 4.0)
    }

    @Test("inserting at the tail with no next returns prev + 1")
    func tailInsert() {
        #expect(OrderIndex.midpoint(prev: 7.0, next: nil) == 8.0)
    }

    @Test("inserting into an empty list returns 1.0")
    func emptyList() {
        #expect(OrderIndex.midpoint(prev: nil, next: nil) == 1.0)
    }

    @Test("inserting between equal values nudges by epsilon")
    func equalValues() {
        // Edge case: shouldn't happen if rebalance is healthy, but guard anyway.
        let result = OrderIndex.midpoint(prev: 3.0, next: 3.0)
        #expect(result > 3.0)
    }
}

@Suite("OrderIndex.manualThenDueOrder")
@MainActor
struct ManualThenDueOrderTests {

    private func task(order: Double?, due: Date?, created: Date) -> TaskItem {
        let item = TaskItem(title: "t", dueAt: due, orderIndex: order)
        item.createdAt = created
        return item
    }

    @Test("lower manual orderIndex sorts first")
    func manualOrderWins() {
        let base = Date(timeIntervalSince1970: 1_777_000_000)
        let a = task(order: 1.0, due: base.addingTimeInterval(9999), created: base)
        let b = task(order: 2.0, due: base, created: base)
        #expect(OrderIndex.manualThenDueOrder(a, b))
        #expect(!OrderIndex.manualThenDueOrder(b, a))
    }

    @Test("a manually-ordered task sorts ahead of an un-ordered one")
    func orderedBeforeUnordered() {
        let base = Date(timeIntervalSince1970: 1_777_000_000)
        // The un-ordered task is due earlier, yet the ordered one still wins.
        let ordered = task(order: 5.0, due: base.addingTimeInterval(9999), created: base)
        let unordered = task(order: nil, due: base, created: base)
        #expect(OrderIndex.manualThenDueOrder(ordered, unordered))
        #expect(!OrderIndex.manualThenDueOrder(unordered, ordered))
    }

    @Test("with no manual order, earlier dueAt sorts first")
    func fallsBackToDueDate() {
        let base = Date(timeIntervalSince1970: 1_777_000_000)
        let earlier = task(order: nil, due: base, created: base.addingTimeInterval(50))
        let later = task(order: nil, due: base.addingTimeInterval(3600), created: base)
        #expect(OrderIndex.manualThenDueOrder(earlier, later))
        #expect(!OrderIndex.manualThenDueOrder(later, earlier))
    }

    @Test("with no manual order and no dueAt, earlier createdAt sorts first")
    func fallsBackToCreatedAt() {
        let base = Date(timeIntervalSince1970: 1_777_000_000)
        let older = task(order: nil, due: nil, created: base)
        let newer = task(order: nil, due: nil, created: base.addingTimeInterval(60))
        #expect(OrderIndex.manualThenDueOrder(older, newer))
        #expect(!OrderIndex.manualThenDueOrder(newer, older))
    }
}
