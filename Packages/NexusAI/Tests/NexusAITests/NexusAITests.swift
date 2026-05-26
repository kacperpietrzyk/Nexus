import Testing

@testable import NexusAI

@Test func packageVersion_isDefinedAndNonEmpty() {
    #expect(NexusAI.version.isEmpty == false)
    #expect(NexusAI.version.contains("."))
}
