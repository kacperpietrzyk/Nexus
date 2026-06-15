import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@MainActor
struct LinkDTOTests {
    @Test("maps a Link to snake_case DTO fields")
    func mapsLink() throws {
        let from = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let to = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let link = Link(from: (.task, from), to: (.note, to), linkKind: .mentions, order: 3)
        let dto = LinkDTO(from: link)
        #expect(dto.fromID == from.uuidString)
        #expect(dto.fromKind == "task")
        #expect(dto.toID == to.uuidString)
        #expect(dto.toKind == "note")
        #expect(dto.linkKind == "mentions")
        #expect(dto.order == 3)
    }
}
