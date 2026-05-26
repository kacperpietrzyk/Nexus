import Foundation
import Testing

@testable import TasksFeature

@Suite("LocalePhrases dispatch")
struct LocalePhrasesTests {
    @Test("Polish locale returns polish table")
    func polishDispatch() {
        let table = LocalePhrases.table(for: Locale(identifier: "pl_PL"))
        #expect(table.languageCode == "pl")
    }

    @Test("English locale returns english table")
    func englishDispatch() {
        let table = LocalePhrases.table(for: Locale(identifier: "en_US"))
        #expect(table.languageCode == "en")
    }

    @Test("unknown locale falls back to english")
    func unknownFallsBackToEnglish() {
        let table = LocalePhrases.table(for: Locale(identifier: "ja_JP"))
        #expect(table.languageCode == "en")
    }

    @Test("Polish table has core date keywords")
    func polishHasJutro() {
        #expect(LocalePhrases.polish.relativeDays["jutro"] == 1)
    }

    @Test("English table has core date keywords")
    func englishHasTomorrow() {
        #expect(LocalePhrases.english.relativeDays["tomorrow"] == 1)
    }
}
