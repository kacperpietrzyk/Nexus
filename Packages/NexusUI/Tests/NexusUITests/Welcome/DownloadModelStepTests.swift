import Foundation
import Testing

@testable import NexusUI

#if !os(watchOS)

import NexusAI

@Suite("DownloadModelStep")
@MainActor
struct DownloadModelStepTests {
    @Test("applyDefaultRecommendation sets tier IDs and clears skip flag")
    func downloadModelStepPicksRecommendedFromTierDetector() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        let tier = DeviceTier(
            recommendedChat: "qwen3.5-9b-instruct-4bit",
            recommendedEmbedder: "multilingual-e5-large"
        )
        let view = try DownloadModelStep(state: state, tier: tier)
        view.applyDefaultRecommendation()
        #expect(state.selectedChatModelID == "qwen3.5-9b-instruct-4bit")
        #expect(state.selectedEmbedderID == "multilingual-e5-large")
        #expect(state.skipMLX == false)
    }

    @Test("applySkipPath clears selections and sets skipMLX")
    func downloadModelStepSkipPathLeavesSelectionsNil() throws {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        let tier = DeviceTier(
            recommendedChat: "qwen3.5-9b-instruct-4bit",
            recommendedEmbedder: "multilingual-e5-large"
        )
        let view = try DownloadModelStep(state: state, tier: tier)
        view.applySkipPath()
        #expect(state.selectedChatModelID == nil)
        #expect(state.selectedEmbedderID == nil)
        #expect(state.skipMLX == true)
    }
}

#endif
