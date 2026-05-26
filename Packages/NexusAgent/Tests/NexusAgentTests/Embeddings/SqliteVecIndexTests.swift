import Foundation
import Testing

@testable import NexusAgent

@Suite struct SqliteVecIndexTests {
    @Test func upsertAndSearchReturnsNearestHit() throws {
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        let nearID = UUID()
        let farID = UUID()

        try index.upsert(id: nearID, vector: makeVector([0.1, 0.1, 0.1, 0.1]))
        try index.upsert(id: farID, vector: makeVector([0.9, 0.9, 0.9, 0.9]))

        let hits = try index.search(query: makeVector([0.1, 0.1, 0.1, 0.1]), limit: 2)

        #expect(hits.map(\.itemID) == [nearID, farID])
        #expect((hits.first?.distance ?? 1) <= (hits.last?.distance ?? 0))
    }

    @Test func rejectsDimensionMismatchOnUpsertAndSearch() throws {
        let index = try SqliteVecIndex.inMemory(dimension: 4)

        #expect(throws: SqliteVecIndexError.dimensionMismatch(expectedBytes: 16, actualBytes: 8)) {
            try index.upsert(id: UUID(), vector: makeVector([0.1, 0.2]))
        }

        #expect(throws: SqliteVecIndexError.dimensionMismatch(expectedBytes: 16, actualBytes: 8)) {
            try index.search(query: makeVector([0.1, 0.2]), limit: 1)
        }
    }

    @Test func upsertReplacesExistingVector() throws {
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        let replacedID = UUID()
        let otherID = UUID()

        try index.upsert(id: replacedID, vector: makeVector([0.1, 0.1, 0.1, 0.1]))
        try index.upsert(id: otherID, vector: makeVector([0.9, 0.9, 0.9, 0.9]))
        try index.upsert(id: replacedID, vector: makeVector([0.8, 0.8, 0.8, 0.8]))

        let hits = try index.search(query: makeVector([0.9, 0.9, 0.9, 0.9]), limit: 2)

        #expect(hits.map(\.itemID) == [otherID, replacedID])
    }

    @Test func searchRequiresPositiveLimit() throws {
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        try index.upsert(id: UUID(), vector: makeVector([0.1, 0.1, 0.1, 0.1]))

        #expect(throws: SqliteVecIndexError.invalidLimit(0)) {
            try index.search(query: makeVector([0.1, 0.1, 0.1, 0.1]), limit: 0)
        }
    }

    @Test func deleteRemovesVector() throws {
        let index = try SqliteVecIndex.inMemory(dimension: 4)
        let id = UUID()

        try index.upsert(id: id, vector: makeVector([0.1, 0.1, 0.1, 0.1]))
        try index.delete(id: id)

        let hits = try index.search(query: makeVector([0.1, 0.1, 0.1, 0.1]), limit: 1)
        #expect(hits.isEmpty)
    }
}

private func makeVector(_ floats: [Float]) -> Data {
    floats.withUnsafeBufferPointer { Data(buffer: $0) }
}
