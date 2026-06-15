import Testing

@testable import NexusAgentTools

@MainActor
struct ToolRegistryManifestTests {
    @Test("link enumeration tools are registered")
    func linkToolsRegistered() {
        let names = Set(CoreTaskTools.all().map(\.name))
        #expect(names.contains("links.backlinks"))
        #expect(names.contains("links.outgoing"))
        #expect(names.contains("links.list"))
    }
}
