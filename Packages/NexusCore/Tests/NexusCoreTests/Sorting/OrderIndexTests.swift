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
