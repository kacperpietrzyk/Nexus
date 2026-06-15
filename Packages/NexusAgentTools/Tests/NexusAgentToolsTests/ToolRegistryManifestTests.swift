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

    @Test("tasks.reorder is registered in the core task tools")
    func reorderToolRegistered() {
        #expect(Set(CoreTaskTools.all().map(\.name)).contains("tasks.reorder"))
    }

    @Test("people.suggest_duplicates is registered in the core task tools")
    func suggestDuplicatesToolRegistered() {
        #expect(Set(CoreTaskTools.all().map(\.name)).contains("people.suggest_duplicates"))
    }
}
