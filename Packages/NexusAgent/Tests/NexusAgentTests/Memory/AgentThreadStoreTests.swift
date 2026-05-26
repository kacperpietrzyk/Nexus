import Testing

@testable import NexusAgent

@Suite
struct AgentThreadStoreTests {
    @Test func threadStoreInsertAndList() throws {
        let store = AgentThreadStore(context: try AgentTestSupport.makeContext())
        let id = try store.create(title: "Daily Briefs")

        #expect(try store.allActive().first?.id == id)
    }

    @Test func threadStoreArchive() throws {
        let store = AgentThreadStore(context: try AgentTestSupport.makeContext())
        let id = try store.create(title: "Throwaway")

        try store.archive(id: id)

        #expect(try store.allActive().isEmpty)
        #expect(try store.allArchived().count == 1)
    }
}
