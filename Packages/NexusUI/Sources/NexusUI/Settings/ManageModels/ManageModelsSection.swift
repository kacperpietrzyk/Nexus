import SwiftUI

#if !os(watchOS)

import NexusAI
import NexusCore
import SwiftData

/// The "Manage Models" settings screen: a `Form` with three sections —
///
/// - **Storage**: a `StorageUsageBar` showing on-disk model footprint vs the
///   device's reachable free space.
/// - **Models**: one `ModelRowExpandable` per catalog `ModelManifest`, whose
///   action callbacks dispatch to `ModelDownloadManager`,
///   `ModelManifestLocalState.Store`, and the shared `MLXLifecycleController`.
/// - **Behavior**: `AutoUnloadToggle` + `PreloadChatToggle` + an "Unload now"
///   button driving the shared lifecycle controller.
///
/// Composed at the app root and handed to `NexusSettingsView` through the
/// `manageModelsContent: AnyView?` slot (mirrors `meetingsSettingsContent`),
/// so the shared `AISettingsSection` — reused by NexusAgent — is untouched.
///
/// `localStateStore` is `.standard`-`UserDefaults`-backed, so it observes the
/// same keys as `WelcomeMLXDownloadCoordinator`'s store; `downloadManager` is
/// the SAME instance the coordinator owns (passed through from the app root),
/// so a Settings-triggered download cannot race a welcome-flow one.
public struct ManageModelsSection: View {
    @Query(sort: \ModelManifest.displayName) private var manifests: [ModelManifest]

    private let localStateStore: ModelManifestLocalState.Store
    private let downloadManager: ModelDownloadManager
    private let lifecycle: MLXLifecycleController
    /// Invoked after an explicit Settings chat re-assign so the running AI
    /// graph rebinds in-process to the newly-assigned model. The Settings
    /// assign writes via `ModelManifestLocalState.Store` directly (NOT through
    /// the download manager's auto-assign path), so it needs its own call to
    /// the same reload hook. App composition roots pass
    /// `{ try? await router.reloadMLXChat() }`; tests/preview omit it.
    private let onChatReassigned: (@MainActor @Sendable () async -> Void)?
    private let onEmbedderReassigned: (@MainActor @Sendable () async -> Void)?

    /// Per-manifest snapshot of `UserDefaults`-backed `ModelManifestLocalState`,
    /// keyed by manifest ID. Populated on `.onAppear` and refreshed after every
    /// store mutation (assign / download / delete) and whenever the manifest list
    /// changes. Using a snapshot dict means SwiftUI re-evaluates `body` via the
    /// `@State` property change — which diffs content and preserves row
    /// identity — instead of the old `.id(refreshToken)` approach that tore down
    /// the entire Form subtree and collapsed any expanded rows.
    @State private var snapshots: [String: ModelManifestLocalState] = [:]

    /// Live, `@Observable` progress handles for in-flight downloads, keyed by
    /// manifest ID. Seeded when a download starts (and on appear, by re-attaching
    /// to any transfer already running in `downloadManager`) and cleared when the
    /// transfer reaches a terminal state. Passing the handle to the row is what
    /// makes the percent move — the `UserDefaults` snapshot only holds the final
    /// status.
    @State private var activeProgress: [String: ModelDownloadProgress] = [:]

    public init(
        localStateStore: ModelManifestLocalState.Store,
        downloadManager: ModelDownloadManager,
        lifecycle: MLXLifecycleController,
        onChatReassigned: (@MainActor @Sendable () async -> Void)? = nil,
        onEmbedderReassigned: (@MainActor @Sendable () async -> Void)? = nil
    ) {
        self.localStateStore = localStateStore
        self.downloadManager = downloadManager
        self.lifecycle = lifecycle
        self.onChatReassigned = onChatReassigned
        self.onEmbedderReassigned = onEmbedderReassigned
    }

    public var body: some View {
        // Shared chrome: the container supplies the "Manage Models" title and
        // the back affordance (kept — this view is pushed as a NavigationLink
        // from iOS Settings and embedded in the macOS in-shell AI & Models
        // panel). Inside, each logical group is a Liquid `LiquidGlassCard(title:)`
        // whose title carries the section header and whose glass supplies its
        // own elevation + edge padding.
        NexusSettingsDetailContainer(title: "Manage Models") {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                storageSection
                modelsSection
                behaviorSection
            }
        }
        .onAppear {
            reloadSnapshots()
            reattachInflightProgress()
            reconcileInterruptedDownloads()
        }
        .onChange(of: manifests.map(\.id)) { reloadSnapshots() }
    }

    private var storageSection: some View {
        LiquidGlassCard("Storage") {
            let storage = Self.storageUsage(
                manifests: manifests,
                localStateStore: localStateStore
            )
            StorageUsageBar(usedGB: storage.usedGB, totalGB: storage.totalGB)
        }
    }

    @ViewBuilder
    private var modelsSection: some View {
        LiquidGlassCard("Models") {
            if manifests.isEmpty {
                // No catalog model present. Downloads live on the model
                // Catalog, not here — so this stays a neutral empty state
                // with no download affordance (backend gate).
                NexusEmptyState(
                    systemImage: "cpu",
                    title: "No models yet",
                    message: "Downloaded models appear here once added from the catalog."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(manifests.enumerated()), id: \.element.id) { index, manifest in
                        if index > 0 {
                            Divider()
                                .overlay(DS.ColorToken.strokeHairline)
                        }
                        ModelRowExpandable(
                            manifest: manifest,
                            localState: snapshots[manifest.id]
                                ?? localStateStore.load(manifestID: manifest.id),
                            progress: activeProgress[manifest.id],
                            onAssignChat: {
                                assign(manifest, keyPath: \.assignedAsChat)
                                if let hook = onChatReassigned {
                                    Task { await hook() }
                                }
                            },
                            onAssignEmbedder: {
                                assign(manifest, keyPath: \.assignedAsEmbedder)
                                if let hook = onEmbedderReassigned {
                                    Task { await hook() }
                                }
                            },
                            onDownload: { Task { await download(manifest) } },
                            onDelete: { delete(manifest) },
                            onReDownload: { Task { await reDownload(manifest) } },
                            onDownloadFinished: { downloadFinished(manifest) }
                        )
                        .padding(.vertical, DS.Space.s)
                    }
                }
            }
        }
    }

    private var behaviorSection: some View {
        LiquidGlassCard("Behavior") {
            VStack(alignment: .leading, spacing: 0) {
                AutoUnloadToggle()
                    .padding(.vertical, DS.Space.s)
                Divider()
                    .overlay(DS.ColorToken.strokeHairline)
                PreloadChatToggle()
                    .padding(.vertical, DS.Space.s)
                Divider()
                    .overlay(DS.ColorToken.strokeHairline)
                Button("Unload now") { lifecycle.unloadAll() }
                    .buttonStyle(NexusPressableButtonStyle())
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .padding(.vertical, DS.Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                    .overlay(DS.ColorToken.strokeHairline)
                Text("Unloading frees model RAM immediately; the next request reloads on demand.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)
            }
        }
    }

    // MARK: - Storage math (pure, unit-testable)

    /// The clamped values fed to `StorageUsageBar`.
    public struct StorageUsage: Equatable, Sendable {
        public let usedGB: Double
        public let totalGB: Double
    }

    /// Storage semantic: `used` = Σ on-disk size of downloaded models;
    /// `total` = used + the device's remaining reachable free space (so the
    /// bar reads "models occupy X of Y, where Y = model footprint + free
    /// space left"). `max(total, used)` then `min(used, total)` enforce the
    /// `0 ≤ used ≤ total` invariant the `StorageUsageBar` `ProgressView`
    /// requires even if the capacity probe returns 0 (Task 25 carry-forward).
    static func storageUsage(
        manifests: [ModelManifest],
        localStateStore: ModelManifestLocalState.Store,
        freeGBProvider: () -> Int = {
            (try? FileManager.default.availableCapacityGBForAppSupport()) ?? 0
        }
    ) -> StorageUsage {
        let used =
            manifests
            .filter { localStateStore.load(manifestID: $0.id).status == .downloaded }
            .reduce(0.0) { $0 + $1.sizeGB }
        let total = max(used + Double(freeGBProvider()), used)
        return StorageUsage(usedGB: min(used, total), totalGB: total)
    }

    /// Returns per-manifest local-state snapshots for every supplied manifest,
    /// loaded from the given store. Pure and unit-testable (same precedent as
    /// `storageUsage`). Used internally by `reloadSnapshots()` to rebuild the
    /// `snapshots` dict after each store mutation.
    static func currentSnapshots(
        manifests: [ModelManifest],
        localStateStore: ModelManifestLocalState.Store
    ) -> [String: ModelManifestLocalState] {
        manifests.reduce(into: [:]) { dict, manifest in
            dict[manifest.id] = localStateStore.load(manifestID: manifest.id)
        }
    }

    private func reloadSnapshots() {
        snapshots = Self.currentSnapshots(manifests: manifests, localStateStore: localStateStore)
    }

    // MARK: - Actions

    /// Sets one mutually-exclusive assignment flag. The store auto-clears the
    /// same flag on every other manifest on save, so this only loads, sets,
    /// and saves — no manual fan-out clearing needed.
    private func assign(
        _ manifest: ModelManifest,
        keyPath: WritableKeyPath<ModelManifestLocalState, Bool>
    ) {
        var state = localStateStore.load(manifestID: manifest.id)
        state[keyPath: keyPath] = true
        localStateStore.save(manifestID: manifest.id, state: state)
        reloadSnapshots()
    }

    private func download(_ manifest: ModelManifest) async {
        do {
            let progress = try await downloadManager.startDownload(
                manifestID: manifest.id,
                hfPath: manifest.hfPath,
                totalBytes: Int64(manifest.sizeGB * 1_073_741_824),
                purpose: manifest.purpose
            )
            // Hold the live handle so the row renders a moving percent and so the
            // terminal-state callback can fire; `startDownload` flipped the store
            // to `.downloading`, which `reloadSnapshots` picks up.
            activeProgress[manifest.id] = progress
            reloadSnapshots()
        } catch {
            // `startDownload` rarely throws synchronously (the real transfer runs
            // detached and records its own failure on the store), but if it does,
            // persist the reason so the row surfaces it instead of swallowing it.
            var state = localStateStore.load(manifestID: manifest.id)
            state.status = .error
            state.downloadError = error.localizedDescription
            localStateStore.save(manifestID: manifest.id, state: state)
            reloadSnapshots()
        }
    }

    /// Re-attaches `activeProgress` to any transfer already running in the shared
    /// `downloadManager` (e.g. one kicked off by the Welcome flow, or still going
    /// after the screen was dismissed and reopened) so the row shows live percent
    /// rather than a stale spinner.
    private func reattachInflightProgress() {
        for manifest in manifests where activeProgress[manifest.id] == nil {
            if let progress = downloadManager.progress(for: manifest.id) {
                activeProgress[manifest.id] = progress
            }
        }
    }

    /// Resets a model stuck in `.downloading` that has NO live transfer back to
    /// `.available`, so the row offers Download again.
    ///
    /// A download whose process was killed mid-flight (app terminated, crash,
    /// or the original hang) leaves `status == .downloading` persisted in
    /// `UserDefaults`. On the next launch the manager's in-flight registry is
    /// empty, so the row would otherwise render a perpetual indeterminate
    /// "Downloading…" spinner with no running transfer and no way to restart —
    /// the `.download` action is hidden in the `.downloading` branch (observed
    /// on-device: Manage Models showed a frozen spinner with nothing actually
    /// downloading). Runs on appear AFTER `reattachInflightProgress()`, and the
    /// `progress(for:) == nil` guard means a genuinely live transfer
    /// (welcome-flow / same-session) keeps its handle and is never reset.
    private func reconcileInterruptedDownloads() {
        let stale = Self.interruptedDownloadIDs(
            manifests: manifests,
            localStateStore: localStateStore,
            hasLiveProgress: {
                activeProgress[$0] != nil || downloadManager.progress(for: $0) != nil
            }
        )
        guard !stale.isEmpty else { return }
        for id in stale {
            var state = localStateStore.load(manifestID: id)
            state.status = .available
            state.downloadError = nil
            localStateStore.save(manifestID: id, state: state)
        }
        reloadSnapshots()
    }

    /// IDs of manifests persisted as `.downloading` but with no live transfer —
    /// interrupted downloads to reset to `.available`. Pure + unit-testable
    /// (same precedent as `storageUsage` / `currentSnapshots`).
    static func interruptedDownloadIDs(
        manifests: [ModelManifest],
        localStateStore: ModelManifestLocalState.Store,
        hasLiveProgress: (String) -> Bool
    ) -> [String] {
        manifests.compactMap { manifest in
            guard !hasLiveProgress(manifest.id),
                localStateStore.load(manifestID: manifest.id).status == .downloading
            else { return nil }
            return manifest.id
        }
    }

    /// Called by a row when its download reaches a terminal state: refresh the
    /// snapshot (so the row flips to Assign/Delete or shows the error) and drop
    /// the now-finished progress handle.
    private func downloadFinished(_ manifest: ModelManifest) {
        activeProgress[manifest.id] = nil
        reloadSnapshots()
    }

    private func reDownload(_ manifest: ModelManifest) async {
        delete(manifest)
        await download(manifest)
    }

    /// Removes the on-disk model folder and resets the local state to
    /// `.available` (clearing path/timestamp) so the row offers Download again.
    private func delete(_ manifest: ModelManifest) {
        var state = localStateStore.load(manifestID: manifest.id)
        if let path = state.localFolderPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        state.status = .available
        state.localFolderPath = nil
        state.downloadedAt = nil
        state.downloadProgressPercent = 0
        state.downloadError = nil
        localStateStore.save(manifestID: manifest.id, state: state)
        reloadSnapshots()
    }
}

#endif
