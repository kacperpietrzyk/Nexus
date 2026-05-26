import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusSync

@MainActor
@Test func nexusSchemaV1_versionIdentifier_is_1_0_0() {
    #expect(NexusSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
}

@MainActor
@Test func nexusSchemaV1_includesCoreAndSyncModels() {
    let names = NexusSchemaV1.models.map { String(describing: $0) }
    #expect(names.contains("Link"))
    #expect(names.contains("DebugItem"))
    #expect(names.contains("ConflictLog"))
}
