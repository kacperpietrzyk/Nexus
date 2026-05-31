import Foundation
import Testing

@testable import NexusAI

@MainActor
@Test func downloadManagerCompletesSuccessfullyWithStubFetcher() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-test-\(#function)"),
        fetcher: StubFetcher(totalBytes: 100, chunkBytes: 25)
    )
    let progress = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 100
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .completed)
    let local = store.load(manifestID: "qwen3.5-4b-instruct-4bit")
    #expect(local.status == .downloaded)
    #expect(local.localFolderPath != nil)
}

@MainActor
@Test func downloadManagerResumesFromExistingBytes() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let fetcher = StubFetcher(totalBytes: 200, chunkBytes: 50)
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-resume-\(#function)"),
        fetcher: fetcher
    )
    let progress = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 200,
        resumeFromBytes: 100
    )
    while progress.state != .completed { try await Task.sleep(for: .milliseconds(20)) }
    #expect(fetcher.firstRequestedByteOffset == 100)
}

@MainActor
@Test func downloadManagerRecordsErrorWhenFetcherThrows() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-throw-\(#function)"),
        fetcher: ThrowingFetcher()
    )
    let progress = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 100
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .failed)
    #expect(progress.errorReason != nil)
    let local = store.load(manifestID: "qwen3.5-4b-instruct-4bit")
    #expect(local.status == .error)
    #expect(local.downloadError != nil)
}

@MainActor
@Test func downloadManagerReentrantStartIsIdempotent() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-reentrant-\(#function)"),
        // Small chunks + per-chunk sleep keeps the first download in-flight
        // long enough for the second call to land mid-download.
        fetcher: StubFetcher(totalBytes: 400, chunkBytes: 20)
    )
    let first = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 400
    )
    // Re-entrant call for the SAME manifestID while the first is running:
    // must return the SAME observable, not spawn a second racing worker.
    let second = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 400
    )
    #expect(first === second)
    #expect(manager.inflightCount == 1)

    while first.state == .active || first.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(first.state == .completed)
    let local = store.load(manifestID: "qwen3.5-4b-instruct-4bit")
    #expect(local.status == .downloaded)
    // Registry must be drained — no leaked/orphaned in-flight entry.
    #expect(manager.inflightCount == 0)
}

@MainActor
@Test func completingChatDownloadAutoAssignsWhenNoChatAssignment() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-autoassign-chat-\(#function)"),
        fetcher: StubFetcher(totalBytes: 100, chunkBytes: 25)
    )
    #expect(store.currentChatAssignment() == nil)
    let progress = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 100,
        purpose: "chat"
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .completed)
    let local = store.load(manifestID: "qwen3.5-4b-instruct-4bit")
    #expect(local.status == .downloaded)
    #expect(local.assignedAsChat == true)
    #expect(store.currentChatAssignment() == "qwen3.5-4b-instruct-4bit")
}

@MainActor
@Test func completingChatDownloadDoesNotOverrideExistingChatAssignment() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    // A different manifest is already the active chat model (e.g. a prior
    // welcome-flow or manual assignment).
    var existing = store.load(manifestID: "qwen3.5-9b-instruct-4bit")
    existing.status = .downloaded
    existing.assignedAsChat = true
    store.save(manifestID: "qwen3.5-9b-instruct-4bit", state: existing)
    #expect(store.currentChatAssignment() == "qwen3.5-9b-instruct-4bit")

    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-autoassign-noclobber-\(#function)"),
        fetcher: StubFetcher(totalBytes: 100, chunkBytes: 25)
    )
    let progress = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 100,
        purpose: "chat"
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .completed)
    // The pre-existing assignment must survive — the new download must NOT
    // become the active chat model, and must NOT clear the existing one.
    #expect(store.currentChatAssignment() == "qwen3.5-9b-instruct-4bit")
    #expect(store.load(manifestID: "qwen3.5-9b-instruct-4bit").assignedAsChat == true)
    #expect(store.load(manifestID: "qwen3.5-4b-instruct-4bit").assignedAsChat == false)
    #expect(store.load(manifestID: "qwen3.5-4b-instruct-4bit").status == .downloaded)
}

@MainActor
@Test func completingEmbedderDownloadAutoAssignsWhenNoEmbedderAssignment() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-autoassign-embedder-\(#function)"),
        fetcher: StubFetcher(totalBytes: 100, chunkBytes: 25)
    )
    #expect(store.currentEmbedderAssignment() == nil)
    let progress = try await manager.startDownload(
        manifestID: "multilingual-e5-large",
        hfPath: "mlx-community/multilingual-e5-large",
        totalBytes: 100,
        purpose: "embedder"
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .completed)
    let local = store.load(manifestID: "multilingual-e5-large")
    #expect(local.status == .downloaded)
    #expect(local.assignedAsEmbedder == true)
    #expect(store.currentEmbedderAssignment() == "multilingual-e5-large")
    // A chat-purpose completion must never touch the embedder assignment and
    // vice versa: this embedder download leaves chat unassigned.
    #expect(store.currentChatAssignment() == nil)
}

@MainActor
@Test func completingEmbedderDownloadDoesNotOverrideExistingEmbedderAssignment() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    // A different manifest is already the active embedder.
    var existing = store.load(manifestID: "bge-small-en")
    existing.status = .downloaded
    existing.assignedAsEmbedder = true
    store.save(manifestID: "bge-small-en", state: existing)
    #expect(store.currentEmbedderAssignment() == "bge-small-en")

    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-autoassign-emb-noclobber-\(#function)"),
        fetcher: StubFetcher(totalBytes: 100, chunkBytes: 25)
    )
    let progress = try await manager.startDownload(
        manifestID: "multilingual-e5-large",
        hfPath: "mlx-community/multilingual-e5-large",
        totalBytes: 100,
        purpose: "embedder"
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .completed)
    // The pre-existing embedder assignment must survive untouched.
    #expect(store.currentEmbedderAssignment() == "bge-small-en")
    #expect(store.load(manifestID: "bge-small-en").assignedAsEmbedder == true)
    #expect(store.load(manifestID: "multilingual-e5-large").assignedAsEmbedder == false)
    #expect(store.load(manifestID: "multilingual-e5-large").status == .downloaded)
}

@MainActor
@Test func completingDownloadWithoutExplicitPurposeDoesNotAutoAssign() async throws {
    let store = ModelManifestLocalState.Store(defaults: makeIsolatedDefaults(#function))
    let manager = ModelDownloadManager(
        localStateStore: store,
        modelsRoot: URL(fileURLWithPath: NSTemporaryDirectory()).appending(
            path: "nexus-noassign-default-\(#function)"),
        fetcher: StubFetcher(totalBytes: 100, chunkBytes: 25)
    )
    #expect(store.currentChatAssignment() == nil)
    #expect(store.currentEmbedderAssignment() == nil)
    // No `purpose:` argument — the default is a no-op sentinel, so a caller
    // that forgets the argument must NOT have its download silently activated.
    let progress = try await manager.startDownload(
        manifestID: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        totalBytes: 100
    )
    while progress.state == .active || progress.state == .pending {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(progress.state == .completed)
    // Non-vacuous: the download DID complete (status downloaded) yet auto-assign
    // was deliberately skipped — both assignment slots remain empty.
    let local = store.load(manifestID: "qwen3.5-4b-instruct-4bit")
    #expect(local.status == .downloaded)
    #expect(local.assignedAsChat == false)
    #expect(local.assignedAsEmbedder == false)
    #expect(store.currentChatAssignment() == nil)
    #expect(store.currentEmbedderAssignment() == nil)
}

private func makeIsolatedDefaults(_ suite: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

final class StubFetcher: ModelFileFetching, @unchecked Sendable {
    let totalBytes: Int64
    let chunkBytes: Int64
    private(set) var firstRequestedByteOffset: Int64 = -1
    init(totalBytes: Int64, chunkBytes: Int64) {
        self.totalBytes = totalBytes
        self.chunkBytes = chunkBytes
    }
    func fetch(
        hfPath: String, toFile destination: URL, startingAtByte byteOffset: Int64,
        totalBytes: Int64, onProgress: @Sendable (Int64) -> Void
    ) async throws {
        if firstRequestedByteOffset < 0 { firstRequestedByteOffset = byteOffset }
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        var written = byteOffset
        while written < totalBytes {
            let next = min(written + chunkBytes, totalBytes)
            try handle.write(contentsOf: Data(count: Int(next - written)))
            written = next
            onProgress(written)
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Fetcher that always throws a non-cancellation error, to lock the
/// `.error` + `markFailed` classification path.
struct ThrowingFetcher: ModelFileFetching {
    struct FetchFailure: Error {}
    func fetch(
        hfPath: String, toFile destination: URL, startingAtByte byteOffset: Int64,
        totalBytes: Int64, onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        throw FetchFailure()
    }
}

@Suite("LiveHFFetcher weight validation")
struct LiveHFFetcherWeightValidationTests {
    private func tempDir(_ name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-weights-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("passes when a non-empty safetensors file is present")
    func passesWithWeights() throws {
        let dir = try tempDir("ok")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(count: 16).write(to: dir.appending(path: "model.safetensors"))
        // Should not throw.
        try LiveHFFetcher.validateWeightsLanded(in: dir, hfPath: "org/model")
    }

    @Test("throws when only sidecars/config landed (no weights)")
    func throwsWithoutWeights() throws {
        let dir = try tempDir("sidecars")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("{}".utf8).write(to: dir.appending(path: "config.json"))
        try Data("vocab".utf8).write(to: dir.appending(path: "tokenizer.json"))
        #expect(throws: ModelDownloadError.self) {
            try LiveHFFetcher.validateWeightsLanded(in: dir, hfPath: "org/model")
        }
    }

    @Test("throws when the safetensors file is empty")
    func throwsWithEmptyWeights() throws {
        let dir = try tempDir("empty")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appending(path: "model.safetensors"))
        #expect(throws: ModelDownloadError.self) {
            try LiveHFFetcher.validateWeightsLanded(in: dir, hfPath: "org/model")
        }
    }
}
