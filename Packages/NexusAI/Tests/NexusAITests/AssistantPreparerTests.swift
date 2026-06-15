import Foundation
import Testing

@testable import NexusAI

@MainActor
@Suite struct AssistantPreparerTests {
    final class RecordingFetcher: ModelFileFetching, @unchecked Sendable {
        var fetched: [String] = []
        func fetch(
            hfPath: String,
            toFile destination: URL,
            startingAtByte: Int64,
            totalBytes: Int64,
            onProgress: @escaping @Sendable (Int64) -> Void
        ) async throws {
            fetched.append(hfPath)
            onProgress(totalBytes)
        }
    }

    @Test func skipsAlreadyDownloadedRoles() async throws {
        let defaults = UserDefaults(suiteName: "prep-test-1")!
        let store = ModelManifestLocalState.Store(defaults: defaults)
        store.save(manifestID: "chat-id", state: .init(status: .downloaded, assignedAsChat: true))
        store.save(manifestID: "emb-id", state: .init(status: .downloaded, assignedAsEmbedder: true))
        let fetcher = RecordingFetcher()
        let mgr = ModelDownloadManager(
            localStateStore: store,
            modelsRoot: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString),
            fetcher: fetcher)
        let set = ResolvedModelSet(
            chatManifestID: "chat-id", chatHFPath: "x/chat", chatContextLength: 1, chatSizeGB: 1,
            embedderManifestID: "emb-id", embedderHFPath: "x/emb", embedderSizeGB: 1)
        let preparer = AssistantPreparer(resolvedSet: set, downloadManager: mgr, localStateStore: store)
        try await preparer.prepareIfNeeded()
        #expect(fetcher.fetched.isEmpty)
    }
}
