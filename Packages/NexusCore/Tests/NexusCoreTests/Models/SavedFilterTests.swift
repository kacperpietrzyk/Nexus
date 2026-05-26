import Foundation
import Testing

@testable import NexusCore

@Suite("SavedFilter")
struct SavedFilterTests {
    @Test("decodedDefinition returns the stored definition")
    func decodedDefinitionReturnsStoredDefinition() throws {
        let expected = FilterDefinition.and([.byTag("work"), .priorityAtLeast(.medium)])
        let filter = try SavedFilter(name: "Work", definition: expected)

        #expect(try filter.decodedDefinition() == expected)
        #expect(filter.definition == expected)
    }

    @Test("decodedDefinition throws while lossy definition falls back for corrupt data")
    func decodedDefinitionThrowsForCorruptData() throws {
        let filter = try SavedFilter(name: "Broken", definition: .byTag("work"))
        filter.definitionJSON = Data("not-json".utf8)

        var didThrow = false
        do {
            _ = try filter.decodedDefinition()
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(filter.definition == .unsorted)
    }
}
