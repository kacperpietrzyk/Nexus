import Foundation
import Testing
@testable import NexusAI

@Suite struct ModelStoreReconcilerTests {
    /// Build a temp roots tree; return (roots, tempDir) — caller removes tempDir.
    static func makeRoots() throws -> (ModelStorageRoots, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "reclaim-test-\(UUID().uuidString)")
        let models = tmp.appending(path: "Models")
        let roots = ModelStorageRoots(
            managedModels: models,
            hubCache: tmp.appending(path: "huggingface/hub"),
            whisperKit: tmp.appending(path: "WhisperKit/whisperkit-coreml"),
            stagingCache: models.appending(path: ".hf-cache")
        )
        for url in [roots.managedModels, roots.hubCache, roots.whisperKit] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return (roots, tmp)
    }

    /// Write a 1-byte file inside `<root>/<name>/weights.bin`.
    static func seedModelDir(_ root: URL, _ name: String) throws {
        let dir = root.appending(path: name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data([0x42]).write(to: dir.appending(path: "weights.bin"))
    }

    static func resolvedSet(chat: String, embedder: String) -> ResolvedModelSet {
        ResolvedModelSet(
            chatManifestID: chat, chatHFPath: "org/\(chat)", chatContextLength: 4096,
            chatSizeGB: 5, embedderManifestID: embedder, embedderHFPath: "org/\(embedder)",
            embedderSizeGB: 1)
    }

    @Test func classifiesCanonicalOrphanAndHubCache() throws {
        let (roots, tmp) = try Self.makeRoots()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        let store = ModelManifestLocalState.Store(defaults: defaults)

        try Self.seedModelDir(roots.managedModels, "gemma-e4b")  // canonical chat
        try Self.seedModelDir(roots.managedModels, "bge-small")  // canonical embedder
        try Self.seedModelDir(roots.managedModels, "qwen3.5-27b-4bit")  // stale chat
        try Self.seedModelDir(roots.hubCache, "models--mlx-community--gemma-4-e4b-it-4bit")
        // canonical chat IS downloaded:
        store.save(
            manifestID: "gemma-e4b",
            state: ModelManifestLocalState(status: .downloaded, assignedAsChat: true))

        let reconciler = ModelStoreReconciler(
            roots: roots, store: store,
            canonical: Self.resolvedSet(chat: "gemma-e4b", embedder: "bge-small"),
            whisperVariant: "openai_whisper-base")
        let byID = Dictionary(uniqueKeysWithValues: reconciler.scan().map { ($0.id, $0.classification) })

        #expect(byID["gemma-e4b"] == .canonical)
        #expect(byID["bge-small"] == .canonical)
        #expect(byID["qwen3.5-27b-4bit"] == .orphan)  // new chat present ⇒ stale is orphan
        #expect(byID["models--mlx-community--gemma-4-e4b-it-4bit"] == .orphan)  // hub cache always orphan
    }

    @Test func protectsStaleChatUntilCanonicalDownloaded() throws {
        let (roots, tmp) = try Self.makeRoots()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        let store = ModelManifestLocalState.Store(defaults: defaults)

        try Self.seedModelDir(roots.managedModels, "qwen3.5-27b-4bit")  // old chat, still active
        // old chat is the current assignment AND new chat is NOT downloaded:
        store.save(
            manifestID: "qwen3.5-27b-4bit",
            state: ModelManifestLocalState(status: .downloaded, assignedAsChat: true))

        let reconciler = ModelStoreReconciler(
            roots: roots, store: store,
            canonical: Self.resolvedSet(chat: "gemma-e4b", embedder: "bge-small"),
            whisperVariant: "openai_whisper-base")
        let byID = Dictionary(uniqueKeysWithValues: reconciler.scan().map { ($0.id, $0.classification) })

        #expect(byID["qwen3.5-27b-4bit"] == .staleButActive)  // protected: it's the only working chat
    }

    @Test func flagsInFlightDownload() throws {
        let (roots, tmp) = try Self.makeRoots()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        let store = ModelManifestLocalState.Store(defaults: defaults)

        try Self.seedModelDir(roots.managedModels, "gemma-e4b")
        store.save(manifestID: "gemma-e4b", state: ModelManifestLocalState(status: .downloading))

        let reconciler = ModelStoreReconciler(
            roots: roots, store: store,
            canonical: Self.resolvedSet(chat: "gemma-e4b", embedder: "bge-small"),
            whisperVariant: "openai_whisper-base")
        let byID = Dictionary(uniqueKeysWithValues: reconciler.scan().map { ($0.id, $0.classification) })

        #expect(byID["gemma-e4b"] == .inFlight)
    }

    @Test func reclaimOrphansRemovesOnlyOrphans() throws {
        let (roots, tmp) = try Self.makeRoots()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        let store = ModelManifestLocalState.Store(defaults: defaults)

        try Self.seedModelDir(roots.managedModels, "gemma-e4b")  // canonical
        try Self.seedModelDir(roots.managedModels, "qwen3.5-27b-4bit")  // orphan (new present)
        try Self.seedModelDir(roots.hubCache, "models--mlx-community--Qwen3.5-27B-4bit")  // orphan
        store.save(
            manifestID: "gemma-e4b",
            state: ModelManifestLocalState(status: .downloaded, assignedAsChat: true))

        let reconciler = ModelStoreReconciler(
            roots: roots, store: store,
            canonical: Self.resolvedSet(chat: "gemma-e4b", embedder: "bge-small"),
            whisperVariant: "openai_whisper-base")
        let result = reconciler.reclaimOrphans()

        #expect(result.failures.isEmpty)
        #expect(result.freedBytes == 2)  // two 1-byte orphan files
        #expect(FileManager.default.fileExists(atPath: roots.managedModels.appending(path: "gemma-e4b").path))
        #expect(!FileManager.default.fileExists(atPath: roots.managedModels.appending(path: "qwen3.5-27b-4bit").path))
        #expect(
            !FileManager.default.fileExists(
                atPath: roots.hubCache.appending(path: "models--mlx-community--Qwen3.5-27B-4bit").path))
    }

    @Test func migrationProtectsOldChatUntilNewDownloaded() throws {
        let (roots, tmp) = try Self.makeRoots()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        let store = ModelManifestLocalState.Store(defaults: defaults)

        try Self.seedModelDir(roots.managedModels, "qwen3.5-27b-4bit")
        store.save(
            manifestID: "qwen3.5-27b-4bit",
            state: ModelManifestLocalState(status: .downloaded, assignedAsChat: true))

        let reconciler = ModelStoreReconciler(
            roots: roots, store: store,
            canonical: Self.resolvedSet(chat: "gemma-e4b", embedder: "bge-small"),
            whisperVariant: "openai_whisper-base")

        // New chat NOT downloaded ⇒ old chat survives.
        _ = reconciler.reclaimOrphans()
        #expect(
            FileManager.default.fileExists(
                atPath: roots.managedModels.appending(path: "qwen3.5-27b-4bit").path))

        // New chat downloaded ⇒ next sweep reclaims the old chat.
        try Self.seedModelDir(roots.managedModels, "gemma-e4b")
        store.save(
            manifestID: "gemma-e4b",
            state: ModelManifestLocalState(status: .downloaded, assignedAsChat: true))
        _ = reconciler.reclaimOrphans()
        #expect(
            !FileManager.default.fileExists(
                atPath: roots.managedModels.appending(path: "qwen3.5-27b-4bit").path))
    }

    @Test func reclaimByIDRemovesBytesAndResetsState() throws {
        let (roots, tmp) = try Self.makeRoots()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        let store = ModelManifestLocalState.Store(defaults: defaults)

        try Self.seedModelDir(roots.managedModels, "gemma-e4b")
        store.save(
            manifestID: "gemma-e4b",
            state: ModelManifestLocalState(
                status: .downloaded,
                localFolderPath: roots.managedModels.appending(path: "gemma-e4b").path,
                assignedAsChat: true))

        let reconciler = ModelStoreReconciler(
            roots: roots, store: store,
            canonical: Self.resolvedSet(chat: "gemma-e4b", embedder: "bge-small"),
            whisperVariant: "openai_whisper-base")

        let result = reconciler.reclaim(canonicalID: "gemma-e4b")
        #expect(result.failures.isEmpty)
        #expect(result.freedBytes == 1)
        #expect(!FileManager.default.fileExists(atPath: roots.managedModels.appending(path: "gemma-e4b").path))
        // State reset so AssistantReadiness reads .notDownloaded and the band re-offers download.
        #expect(store.load(manifestID: "gemma-e4b").status == .available)
        #expect(store.load(manifestID: "gemma-e4b").localFolderPath == nil)
    }
}
