import Foundation
import Testing

@testable import NexusMeetings

struct CustomVocabularyStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "custom-vocab-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func loadDefaultsToEmpty() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsCustomVocabularyStore(defaults: defaults)
        #expect(store.load().isEmpty)
    }

    @Test func saveThenLoadRoundTrips() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsCustomVocabularyStore(defaults: defaults)
        let entries = [
            CustomVocabularyEntry(term: "threat forge", replacement: "ThreatForge"),
            CustomVocabularyEntry(term: "kube", replacement: "Kube"),
        ]
        store.save(entries)
        #expect(store.load() == entries)
    }

    @Test func entryUsabilityIgnoresBlankTerms() {
        #expect(CustomVocabularyEntry(term: "x", replacement: "").isUsable)
        #expect(CustomVocabularyEntry(term: "  ", replacement: "Y").isUsable == false)
        #expect(CustomVocabularyEntry(term: "", replacement: "Y").isUsable == false)
    }
}
