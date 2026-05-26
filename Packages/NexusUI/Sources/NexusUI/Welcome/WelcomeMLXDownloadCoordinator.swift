import SwiftUI

#if !os(watchOS)

import NexusAI

/// Owns the welcome-flow MLX download wiring so `NexusMacApp` / `NexusiOSApp`
/// don't each re-implement (and bloat with) the same state + catalog + manager
/// retention and the chat-then-embedder kickoff.
///
/// The host app constructs ONE instance in its composition root and retains it
/// for the process lifetime — the kicked-off downloads (multi-GB) must outlive
/// the welcome sheet. `state` is the single `UserDefaults`-backed
/// `WelcomeFlowState` the `DownloadModelStep` binds + persists. `catalog` is
/// `nil` when the bundled `DefaultCatalog.json` failed to decode; the download
/// step is then omitted from the flow entirely rather than rendered degraded.
@MainActor
public final class WelcomeMLXDownloadCoordinator {
    private let state: WelcomeFlowState
    private let catalog: ModelCatalog.CatalogDoc?
    /// `public` so the composition root can hand the SAME manager to
    /// `ManageModelsSection` (Task 27). A fresh `ModelDownloadManager` would
    /// have its own in-memory `inflight` registry and could spawn a second
    /// detached worker writing the same per-manifest folder as a
    /// welcome-flow download still in flight.
    public let manager: ModelDownloadManager

    /// Production convenience: builds the standard manager (live HF fetcher,
    /// default models root) and loads the bundled catalog (`nil` on failure).
    ///
    /// `onChatAssigned` / `onEmbedderAssigned` are forwarded to the owned
    /// `ModelDownloadManager` so a welcome-flow auto-assign rebinds the running
    /// AI graph in-process (Task 27c). The app composition root supplies
    /// `{ try? await router.reloadMLXChat() }` etc.; omitting them (tests) is a
    /// no-op.
    public convenience init(
        onChatAssigned: (@MainActor @Sendable () async -> Void)? = nil,
        onEmbedderAssigned: (@MainActor @Sendable () async -> Void)? = nil
    ) {
        let catalog = try? ModelCatalog.loadDefault()
        let manager = ModelDownloadManager(
            localStateStore: ModelManifestLocalState.Store(),
            modelsRoot: ModelDownloadManager.defaultModelsRoot(),
            fetcher: LiveHFFetcher(),
            onChatAssigned: onChatAssigned,
            onEmbedderAssigned: onEmbedderAssigned
        )
        self.init(
            state: WelcomeFlowState(defaults: .standard),
            catalog: catalog,
            manager: manager
        )
    }

    /// Designated init — injectable for tests.
    public init(
        state: WelcomeFlowState,
        catalog: ModelCatalog.CatalogDoc?,
        manager: ModelDownloadManager
    ) {
        self.state = state
        self.catalog = catalog
        self.manager = manager
    }

    /// The welcome flow's extra screens in display order: the
    /// `DownloadModelStep` first (omitted when the bundled catalog failed to
    /// decode — the flow shape stays valid), then whatever `followedBy`
    /// trailing screens the host appends (e.g. the Mac Meetings step; iOS
    /// passes none). The download step's `onContinue` kicks off the planned
    /// downloads, then calls the injected `advance`.
    public func extraScreens(
        followedBy trailing: [(@escaping () -> Void) -> AnyView] = []
    ) -> [(@escaping () -> Void) -> AnyView] {
        var screens: [(@escaping () -> Void) -> AnyView] = []
        if let catalog {
            screens.append { [state, manager] advance in
                AnyView(
                    DownloadModelStep(
                        state: state,
                        tier: TierDetector.detectCurrent(),
                        catalog: catalog,
                        onContinue: {
                            Self.kickOff(state: state, catalog: catalog, manager: manager)
                            advance()
                        }
                    )
                )
            }
        }
        return screens + trailing
    }

    /// Kicks off the user's chat then embedder download, chat first, via the
    /// retained `ModelDownloadManager`; the transfers run concurrently
    /// (`startDownload` returns immediately). Skip path plans nothing.
    @MainActor
    private static func kickOff(
        state: WelcomeFlowState,
        catalog: ModelCatalog.CatalogDoc,
        manager: ModelDownloadManager
    ) {
        let plan = DownloadModelStep.downloadPlan(state: state, catalog: catalog)
        guard !plan.isEmpty else { return }
        Task { @MainActor in
            for request in plan {
                _ = try? await manager.startDownload(
                    manifestID: request.manifestID,
                    hfPath: request.hfPath,
                    totalBytes: request.totalBytes,
                    purpose: request.purpose
                )
            }
        }
    }
}

#endif
