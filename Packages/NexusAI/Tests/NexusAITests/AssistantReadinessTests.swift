import Foundation
import Testing

@testable import NexusAI

@MainActor
@Suite struct AssistantReadinessTests {
    @Test func notDownloadedWhenNoLocalState() {
        let store = ModelManifestLocalState.Store(defaults: UserDefaults(suiteName: "ar-test-1")!)
        let resolver = AssistantReadinessResolver(localStateStore: store, chatManifestID: "gemma-x")
        #expect(resolver.readiness(progress: nil) == .notDownloaded)
    }

    @Test func readyWhenDownloadedAndAssigned() {
        let defaults = UserDefaults(suiteName: "ar-test-2")!
        let store = ModelManifestLocalState.Store(defaults: defaults)
        store.save(manifestID: "gemma-x", state: .init(status: .downloaded, assignedAsChat: true))
        let resolver = AssistantReadinessResolver(localStateStore: store, chatManifestID: "gemma-x")
        #expect(resolver.readiness(progress: nil) == .ready)
    }
}
