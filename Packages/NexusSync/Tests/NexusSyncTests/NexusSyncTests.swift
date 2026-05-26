import Testing

@testable import NexusSync

@Test func packageVersion_isDefinedAndNonEmpty() {
    #expect(NexusSync.version.isEmpty == false)
    #expect(NexusSync.version.contains("."))
}
