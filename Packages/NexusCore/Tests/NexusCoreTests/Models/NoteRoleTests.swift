import Foundation
import Testing

@testable import NexusCore

@Suite("NoteRole")
struct NoteRoleTests {
    @Test("raw values are stable lowercase strings")
    func rawValuesAreStable() {
        #expect(NoteRole.free.rawValue == "free")
        #expect(NoteRole.projectPage.rawValue == "projectPage")
        #expect(NoteRole.dailyNote.rawValue == "dailyNote")
    }

    @Test("is Codable round-trip")
    func isCodable() throws {
        for role in NoteRole.allCases {
            let encoded = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(NoteRole.self, from: encoded)
            #expect(decoded == role)
        }
    }
}
