import Testing

@testable import NexusUI

@Test func packageVersion_isDefinedAndNonEmpty() {
    #expect(NexusUI.version.isEmpty == false)
    #expect(NexusUI.version.contains("."))
}
