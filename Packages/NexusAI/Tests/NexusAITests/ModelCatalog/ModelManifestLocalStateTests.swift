import Foundation
import Testing

@testable import NexusAI

@Test func localStateRoundTripsViaUserDefaults() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = ModelManifestLocalState.Store(defaults: defaults)

    var state = store.load(manifestID: "qwen3.5-9b-instruct-4bit")
    #expect(state.status == .available)
    #expect(state.localFolderPath == nil)
    #expect(state.assignedAsChat == false)

    state.status = .downloaded
    state.localFolderPath = "/Library/Application Support/Nexus/Models/qwen3.5-9b"
    state.downloadedAt = Date(timeIntervalSince1970: 1_780_000_000)
    state.assignedAsChat = true
    store.save(manifestID: "qwen3.5-9b-instruct-4bit", state: state)

    let loaded = store.load(manifestID: "qwen3.5-9b-instruct-4bit")
    #expect(loaded.status == .downloaded)
    #expect(loaded.localFolderPath?.hasSuffix("/qwen3.5-9b") == true)
    #expect(loaded.downloadedAt?.timeIntervalSince1970 == 1_780_000_000)
    #expect(loaded.assignedAsChat == true)
}

@Test func assigningChatToANewManifestClearsThePrevious() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = ModelManifestLocalState.Store(defaults: defaults)

    var qwen = store.load(manifestID: "qwen3.5-9b-instruct-4bit")
    qwen.status = .downloaded
    qwen.assignedAsChat = true
    store.save(manifestID: "qwen3.5-9b-instruct-4bit", state: qwen)
    #expect(store.currentChatAssignment() == "qwen3.5-9b-instruct-4bit")

    var gemma = store.load(manifestID: "gemma-4-e4b-it-4bit")
    gemma.status = .downloaded
    gemma.assignedAsChat = true
    store.save(manifestID: "gemma-4-e4b-it-4bit", state: gemma)

    let qwenAfter = store.load(manifestID: "qwen3.5-9b-instruct-4bit")
    #expect(qwenAfter.assignedAsChat == false)
    #expect(store.currentChatAssignment() == "gemma-4-e4b-it-4bit")
}

@Test func assigningEmbedderToANewManifestClearsThePrevious() {
    let defaults = UserDefaults(suiteName: #function)!
    defaults.removePersistentDomain(forName: #function)
    let store = ModelManifestLocalState.Store(defaults: defaults)

    // Empty-store baseline (folds in the cheap nil-baseline Minor):
    #expect(store.currentEmbedderAssignment() == nil)

    var e5large = store.load(manifestID: "multilingual-e5-large")
    e5large.status = .downloaded
    e5large.assignedAsEmbedder = true
    store.save(manifestID: "multilingual-e5-large", state: e5large)
    #expect(store.currentEmbedderAssignment() == "multilingual-e5-large")

    var other = store.load(manifestID: "some-other-embedder")
    other.status = .downloaded
    other.assignedAsEmbedder = true
    store.save(manifestID: "some-other-embedder", state: other)

    let e5After = store.load(manifestID: "multilingual-e5-large")
    #expect(e5After.assignedAsEmbedder == false)
    #expect(store.currentEmbedderAssignment() == "some-other-embedder")
    // Cross-role isolation: assigning embedder must not touch chat:
    #expect(store.currentChatAssignment() == nil)
}
