import Foundation
import Testing

@testable import NexusUI

#if !os(watchOS)

@Suite("WelcomeFlowState MLX persistence")
@MainActor
struct WelcomeFlowStateMLXTests {
    @Test("persist and reload MLX selection")
    func welcomeFlowStatePersistsMLXSelection() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        state.selectedChatModelID = "qwen3.5-9b-instruct-4bit"
        state.selectedEmbedderID = "multilingual-e5-large"
        state.skipMLX = false
        state.persist()
        let reloaded = WelcomeFlowState(defaults: defaults)
        #expect(reloaded.selectedChatModelID == "qwen3.5-9b-instruct-4bit")
        #expect(reloaded.selectedEmbedderID == "multilingual-e5-large")
        #expect(reloaded.skipMLX == false)
    }

    @Test("skipMLX true with no selections reloads correctly")
    func welcomeFlowSkipMLXMarkedTrueLeavesSelectionsNil() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let state = WelcomeFlowState(defaults: defaults)
        state.skipMLX = true
        state.persist()
        let reloaded = WelcomeFlowState(defaults: defaults)
        #expect(reloaded.skipMLX == true)
        #expect(reloaded.selectedChatModelID == nil)
        #expect(reloaded.selectedEmbedderID == nil)
    }
}

#endif
