import Foundation
import Testing

@testable import NexusCore

@Test func linkKind_rawValues_areStableLowercaseStrings() {
    #expect(LinkKind.mentions.rawValue == "mentions")
    #expect(LinkKind.actionItem.rawValue == "actionItem")
    #expect(LinkKind.blocks.rawValue == "blocks")
    #expect(LinkKind.child.rawValue == "child")
    #expect(LinkKind.source.rawValue == "source")
    #expect(LinkKind.attachment.rawValue == "attachment")
}

@Test func linkKind_isCodable() throws {
    let encoded = try JSONEncoder().encode(LinkKind.actionItem)
    let decoded = try JSONDecoder().decode(LinkKind.self, from: encoded)
    #expect(decoded == .actionItem)
}
