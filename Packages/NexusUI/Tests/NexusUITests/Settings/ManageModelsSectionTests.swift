import Foundation
import Testing

@testable import NexusUI

#if !os(watchOS)

import NexusAI
import NexusCore

@Suite("ManageModelsSection.currentSnapshots")
@MainActor
struct ManageModelsSectionTests {
    // MARK: - Helpers

    private func makeManifest(id: String, purpose: String = "chat") -> ModelManifest {
        ModelManifest(
            id: id,
            hfPath: "mlx-community/\(id)",
            family: "test",
            displayName: id,
            sizeGB: 1.0,
            recommendedRAMGB: 4,
            contextLength: 4096,
            supportsTools: false,
            supportsVision: false,
            supportedLocales: ["en"],
            purpose: purpose
        )
    }

    private func makeStore(suiteName: String) -> ModelManifestLocalState.Store {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ModelManifestLocalState.Store(defaults: defaults)
    }

    // MARK: - Tests

    @Test("empty manifest list produces empty snapshot dict")
    func emptyManifestsYieldsEmptySnapshots() {
        let store = makeStore(suiteName: #function)
        let result = ManageModelsSection.currentSnapshots(
            manifests: [],
            localStateStore: store
        )
        #expect(result.isEmpty)
    }

    @Test("snapshots keyed by manifest ID reflect persisted state")
    func snapshotsKeyedByManifestID() {
        let store = makeStore(suiteName: #function)
        let m1 = makeManifest(id: "model-a")
        let m2 = makeManifest(id: "model-b")

        // Persist a non-default state for m1
        var state = ModelManifestLocalState()
        state.status = .downloaded
        state.assignedAsChat = true
        store.save(manifestID: "model-a", state: state)

        let snapshots = ManageModelsSection.currentSnapshots(
            manifests: [m1, m2],
            localStateStore: store
        )

        #expect(snapshots["model-a"]?.status == .downloaded)
        #expect(snapshots["model-a"]?.assignedAsChat == true)
        #expect(snapshots["model-b"]?.status == .available)
        #expect(snapshots["model-b"]?.assignedAsChat == false)
    }

    @Test("store mutation is immediately reflected in a fresh currentSnapshots call")
    func mutationReflectedWithoutIdentityNuke() {
        let store = makeStore(suiteName: #function)
        let manifest = makeManifest(id: "model-c")

        // Initial state: not downloaded
        let before = ManageModelsSection.currentSnapshots(
            manifests: [manifest],
            localStateStore: store
        )
        #expect(before["model-c"]?.status == .available)

        // Simulate what delete() does: save .available (already done above for coverage)
        // and what assign() does: set assignedAsChat = true and save
        var state = ModelManifestLocalState(status: .downloaded)
        state.assignedAsChat = true
        store.save(manifestID: "model-c", state: state)

        let after = ManageModelsSection.currentSnapshots(
            manifests: [manifest],
            localStateStore: store
        )

        // The snapshot dict reflects the mutation WITHOUT any view identity change —
        // this is the pure data path exercised by ManageModelsSection.reloadSnapshots().
        #expect(after["model-c"]?.status == .downloaded)
        #expect(after["model-c"]?.assignedAsChat == true)
        // before is unchanged (it was computed before the save)
        #expect(before["model-c"]?.status == .available)
    }

    @Test("assign mutual-exclusion: saving assignedAsChat=true clears other manifests")
    func assignMutualExclusion() {
        let store = makeStore(suiteName: #function)
        let m1 = makeManifest(id: "chat-1")
        let m2 = makeManifest(id: "chat-2")

        // Assign m1 as chat
        var s1 = ModelManifestLocalState(status: .downloaded, assignedAsChat: true)
        store.save(manifestID: "chat-1", state: s1)

        var snap = ManageModelsSection.currentSnapshots(
            manifests: [m1, m2],
            localStateStore: store
        )
        #expect(snap["chat-1"]?.assignedAsChat == true)
        #expect(snap["chat-2"]?.assignedAsChat == false)

        // Re-assign to m2 — store auto-clears m1
        s1 = ModelManifestLocalState(status: .downloaded, assignedAsChat: true)
        store.save(manifestID: "chat-2", state: s1)

        snap = ManageModelsSection.currentSnapshots(
            manifests: [m1, m2],
            localStateStore: store
        )
        #expect(snap["chat-2"]?.assignedAsChat == true)
        #expect(snap["chat-1"]?.assignedAsChat == false)
    }

    @Test("delete semantics: status reverts to .available in the snapshot")
    func deleteSemantics() {
        let store = makeStore(suiteName: #function)
        let manifest = makeManifest(id: "model-d")

        // Pre-condition: model was downloaded
        var state = ModelManifestLocalState(
            status: .downloaded,
            localFolderPath: "/some/path",
            downloadedAt: Date()
        )
        store.save(manifestID: "model-d", state: state)

        // Simulate delete() (FileManager removal is skipped — no real path)
        state.status = .available
        state.localFolderPath = nil
        state.downloadedAt = nil
        state.downloadProgressPercent = 0
        state.downloadError = nil
        store.save(manifestID: "model-d", state: state)

        let snap = ManageModelsSection.currentSnapshots(
            manifests: [manifest],
            localStateStore: store
        )
        #expect(snap["model-d"]?.status == .available)
        #expect(snap["model-d"]?.localFolderPath == nil)
        #expect(snap["model-d"]?.downloadedAt == nil)
    }
}

#endif
