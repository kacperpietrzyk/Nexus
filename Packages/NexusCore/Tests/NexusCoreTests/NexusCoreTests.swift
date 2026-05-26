import Testing

@testable import NexusCore

@Test func packageVersion_isDefinedAndNonEmpty() {
    #expect(NexusCore.version.isEmpty == false)
    #expect(NexusCore.version.contains("."))
}
