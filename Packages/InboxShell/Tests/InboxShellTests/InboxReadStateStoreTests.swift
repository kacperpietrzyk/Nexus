import Foundation
import InboxShell
import Testing

@Suite("InboxReadStateStore")
struct InboxReadStateStoreTests {

    private func makeStore() -> (InboxReadStateStore, UserDefaults) {
        // Isolated suite so the test never touches the app's standard defaults.
        let suiteName = "InboxReadStateStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (InboxReadStateStore(defaults: defaults), defaults)
    }

    @Test("save then load round-trips the id set")
    func roundTrips() {
        let (store, _) = makeStore()
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]

        store.save(ids)

        #expect(store.load() == ids)
    }

    @Test("load returns empty when nothing was saved")
    func loadsEmptyByDefault() {
        let (store, _) = makeStore()
        #expect(store.load().isEmpty)
    }

    @Test("save overwrites the previously persisted set")
    func saveOverwrites() {
        let (store, _) = makeStore()
        let first = UUID()
        let second = UUID()

        store.save([first])
        store.save([second])

        #expect(store.load() == [second])
    }
}
