import Foundation
import Testing

@testable import NexusAI

@Suite struct AssistantReadinessChecklistTests {

    // MARK: - Fixtures

    private func makeSet(chat: String = "gemma-chat", embedder: String = "e5-embed") -> ResolvedModelSet {
        ResolvedModelSet(
            chatManifestID: chat,
            chatHFPath: "org/\(chat)",
            chatContextLength: 1_000,
            chatSizeGB: 7.0,
            embedderManifestID: embedder,
            embedderHFPath: "org/\(embedder)",
            embedderSizeGB: 1.1
        )
    }

    private func store(_ suite: String) -> ModelManifestLocalState.Store {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return ModelManifestLocalState.Store(defaults: defaults)
    }

    private func entry(
        id: String,
        kind: ModelStoreEntry.Kind,
        classification: ModelStoreEntry.Classification,
        size: Int64 = 1_000
    ) -> ModelStoreEntry {
        ModelStoreEntry(
            id: id,
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            sizeBytes: size,
            kind: kind,
            classification: classification
        )
    }

    // MARK: - Required-set selection (DeviceTier, not ResolvedModelSet)

    @Test func onlyRequiredRolesAppear_subEightGigDeviceHasNoChat() {
        let tier = DeviceTier(recommendedChat: nil, recommendedEmbedder: "e5-embed")
        let checklist = AssistantReadinessChecklist(
            tier: tier, resolvedSet: makeSet(), store: store("acl-1"))
        let items = checklist.items(scanEntries: [])
        #expect(items.count == 1)
        #expect(items.first?.role == .embedder)
    }

    @Test func noneRequired_onWatchTier() {
        let tier = DeviceTier(recommendedChat: nil, recommendedEmbedder: nil)
        let checklist = AssistantReadinessChecklist(
            tier: tier, resolvedSet: makeSet(), store: store("acl-2"))
        let items = checklist.items(scanEntries: [])
        #expect(items.isEmpty)
        #expect(checklist.summary(for: items).overall == .noneRequired)
    }

    // MARK: - Disk truth wins over the UserDefaults flag

    @Test func missingWhenFlagSaysDownloadedButNotOnDisk() {
        let s = store("acl-3")
        // The flag lies: status downloaded, but no canonical entry on disk.
        s.save(manifestID: "gemma-chat", state: .init(status: .downloaded, assignedAsChat: true))
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: "e5-embed")
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [])  // disk empty
        let chat = items.first { $0.role == .chat }
        #expect(chat?.status == .missing)
    }

    @Test func readyWhenCanonicalOnDiskAndFlagDownloaded() {
        let s = store("acl-4")
        s.save(manifestID: "gemma-chat", state: .init(status: .downloaded))
        s.save(manifestID: "e5-embed", state: .init(status: .downloaded))
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: "e5-embed")
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [
            entry(id: "gemma-chat", kind: .chat, classification: .canonical),
            entry(id: "e5-embed", kind: .embedder, classification: .canonical),
        ])
        #expect(items.allSatisfy { $0.status == .ready })
        let summary = checklist.summary(for: items)
        #expect(summary.overall == .ready)
        #expect(summary.readyCount == 2)
        #expect(summary.requiredCount == 2)
    }

    // MARK: - In-progress + error + stale-but-active

    @Test func downloadingReflectsPercent() {
        let s = store("acl-5")
        s.save(
            manifestID: "gemma-chat",
            state: .init(status: .downloading, downloadProgressPercent: 42))
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: nil)
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [
            entry(id: "gemma-chat", kind: .chat, classification: .inFlight)
        ])
        #expect(items.first?.status == .downloading(0.42))
        #expect(checklist.summary(for: items).overall == .downloading)
    }

    @Test func failedSurfacesError() {
        let s = store("acl-6")
        s.save(
            manifestID: "gemma-chat",
            state: .init(status: .error, downloadError: "disk full"))
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: nil)
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [])
        #expect(items.first?.status == .failed("disk full"))
        #expect(checklist.summary(for: items).overall == .failed)
    }

    @Test func staleButActiveCountsAsUpdatingNotMissing() {
        let s = store("acl-7")
        // Canonical chat not downloaded; an older chat model is the only working one.
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: nil)
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [
            entry(id: "old-gemma", kind: .chat, classification: .staleButActive)
        ])
        #expect(items.first?.status == .updating)
        // Updating still functions → counts toward ready, overall stays ready.
        let summary = checklist.summary(for: items)
        #expect(summary.readyCount == 1)
        #expect(summary.overall == .ready)
    }

    @Test func staleUnknownTaggedChatCountsAsUpdatingNotMissing() {
        // Regression: the reconciler tags a superseded-but-active chat model with
        // `kind == .unknown` (its id matches neither canonical chat nor embedder),
        // so the checklist must treat an `.unknown`-tagged `.staleButActive` entry as
        // a working older chat — `updating`, not `missing`/broken — while the canonical
        // chat has not been downloaded yet.
        let s = store("acl-9")
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: nil)
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [
            entry(id: "old-gemma", kind: .unknown, classification: .staleButActive)
        ])
        let chat = items.first { $0.role == .chat }
        #expect(chat?.status == .updating)
        #expect(chat?.status != .missing)
        let summary = checklist.summary(for: items)
        #expect(summary.readyCount == 1)
        #expect(summary.overall == .ready)
        #expect(summary.overall != .incomplete)
    }

    @Test func incompleteWhenMixedReadyAndMissing() {
        let s = store("acl-8")
        s.save(manifestID: "gemma-chat", state: .init(status: .downloaded))
        let tier = DeviceTier(recommendedChat: "gemma-chat", recommendedEmbedder: "e5-embed")
        let checklist = AssistantReadinessChecklist(tier: tier, resolvedSet: makeSet(), store: s)
        let items = checklist.items(scanEntries: [
            entry(id: "gemma-chat", kind: .chat, classification: .canonical)
            // embedder absent → missing
        ])
        #expect(checklist.summary(for: items).overall == .incomplete)
    }
}
