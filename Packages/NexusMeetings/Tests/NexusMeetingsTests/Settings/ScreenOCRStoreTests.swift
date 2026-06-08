import Foundation
import Testing

@testable import NexusMeetings

struct ScreenOCRStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "screen-ocr-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func defaultsToDisabled() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsScreenOCRStore(defaults: defaults)
        #expect(store.isEnabled() == false)
    }

    @Test func saveThenLoadRoundTrips() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsScreenOCRStore(defaults: defaults)
        store.save(enabled: true)
        #expect(store.isEnabled())
        store.save(enabled: false)
        #expect(store.isEnabled() == false)
    }
}
