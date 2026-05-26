import Foundation
import Testing

@testable import TasksFeature

@Suite("PencilRecognitionLanguages")
struct PencilRecognitionLanguagesTests {

    @Test("Polish locale without region maps to Vision-supported tag")
    func polishLocaleWithoutRegionMapsToVisionSupportedTag() {
        #expect(PencilRecognitionLanguages.make(for: Locale(identifier: "pl")) == ["pl-PL", "en-US"])
    }

    @Test("Polish locale with underscore region maps to BCP 47")
    func polishLocaleWithUnderscoreRegionMapsToBCP47() {
        #expect(PencilRecognitionLanguages.make(for: Locale(identifier: "pl_PL")) == ["pl-PL", "en-US"])
    }

    @Test("English US locale avoids duplicate fallback")
    func englishUSLocaleAvoidsDuplicateFallback() {
        #expect(PencilRecognitionLanguages.make(for: Locale(identifier: "en_US")) == ["en-US"])
    }
}
