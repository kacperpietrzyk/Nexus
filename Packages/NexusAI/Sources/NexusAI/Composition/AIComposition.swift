import Foundation
import NexusCore
import SwiftData

/// Composition factory for the production `AIRouter` graph. Used by
/// `NexusMacApp` and `NexusiOSApp` init blocks; centralizing here keeps the two
/// app files symmetrical and prevents drift as providers/stores evolve.
///
/// Covered by NexusAI package tests and app integration builds.
public enum AIComposition {

    /// Builds the production router with the lightweight cloud-only provider set
    /// + persistent stores. Used by short-lived / memory-constrained processes
    /// (the iOS Share extension, the Meetings helper) that must NOT spin up an
    /// MLX lifecycle, background idle sweep, or memory-guard actor.
    ///
    /// - Parameter container: shared `ModelContainer`, used by
    ///   `PersistentQuotaTracker` for daily quota aggregation.
    public static func makeRouter(container: ModelContainer) -> AIRouter {
        let consent = UserDefaultsConsentStore()
        let quota = PersistentQuotaTracker(modelContainer: container)

        let providers: [any AIProvider] = [
            AppleIntelligenceProvider(),
            WhisperKitProvider(),
        ]
        return AIRouter(
            providers: providers,
            consent: consent,
            quota: quota,
            secrets: KeychainSecretStore()
        )
    }

    #if canImport(Vision)
    /// The full production AI graph for the main Mac / iOS apps: the router
    /// (cloud providers + on-device MLX chat/embedder), the MLX lifecycle
    /// controller, the OS memory-pressure guard, and the OCR pipeline.
    ///
    /// The host App MUST retain this value for its entire lifetime — the
    /// `mlxLifecycle` runs a background idle sweep and the `mlxMemoryGuard`
    /// registers an OS memory-warning observer that is torn down in `deinit`;
    /// dropping the graph silently disables MLX unload-on-pressure.
    public struct AIGraph {
        public let router: AIRouter
        public let mlxLifecycle: MLXLifecycleController
        public let mlxMemoryGuard: MLXMemoryGuard
        public let ocrPipeline: OCRPipeline

        public init(
            router: AIRouter,
            mlxLifecycle: MLXLifecycleController,
            mlxMemoryGuard: MLXMemoryGuard,
            ocrPipeline: OCRPipeline
        ) {
            self.router = router
            self.mlxLifecycle = mlxLifecycle
            self.mlxMemoryGuard = mlxMemoryGuard
            self.ocrPipeline = ocrPipeline
        }
    }
    #else
    /// Non-Vision platforms have no `OCRPipeline`; the graph still carries the
    /// router + MLX lifecycle/guard so callers stay symmetrical.
    public struct AIGraph {
        public let router: AIRouter
        public let mlxLifecycle: MLXLifecycleController
        public let mlxMemoryGuard: MLXMemoryGuard

        public init(
            router: AIRouter,
            mlxLifecycle: MLXLifecycleController,
            mlxMemoryGuard: MLXMemoryGuard
        ) {
            self.router = router
            self.mlxLifecycle = mlxLifecycle
            self.mlxMemoryGuard = mlxMemoryGuard
        }
    }
    #endif

    /// Builds the full production graph: cloud providers + on-device MLX
    /// chat/embedder, the MLX lifecycle controller, the OS memory guard, and the
    /// OCR pipeline. Use from the main Mac / iOS app composition roots ONLY —
    /// the returned `AIGraph` must be retained for the app's lifetime.
    ///
    /// - Parameter container: shared `ModelContainer`, used by
    ///   `PersistentQuotaTracker` for daily quota aggregation.
    public static func makeGraph(container: ModelContainer) -> AIGraph {
        let consent = UserDefaultsConsentStore()
        let quota = PersistentQuotaTracker(modelContainer: container)

        let localState = ModelManifestLocalState.Store()
        let lifecycle = MLXLifecycleController(
            modelsRoot: ModelDownloadManager.defaultModelsRoot(),
            localStateStore: localState
        )
        // Dynamic folder providers: the model folder is re-resolved at every
        // cold load via the lifecycle controller, so a post-launch assignment
        // change (Welcome auto-assign / Settings re-assign) rebinds the next
        // load to the new model instead of the folder captured here. `lifecycle`
        // is captured strongly — it is already retained by the returned
        // `AIGraph`, and the engine holds it strongly anyway, so no new cycle.
        let chatEngine = MLXChatEngine(
            folderProvider: { lifecycle.chatFolderURL() },
            lifecycle: lifecycle
        )
        let embedderEngine = MLXEmbedderEngine(
            folderProvider: { lifecycle.embedderFolderURL() },
            lifecycle: lifecycle
        )
        let mlxChat = MLXProvider(
            engine: chatEngine,
            availabilityProbe: { [weak lifecycle] in lifecycle?.isChatAvailable ?? false }
        )
        let mlxEmbedder = MLXEmbedderProvider(
            engine: embedderEngine,
            availabilityProbe: { [weak lifecycle] in lifecycle?.isEmbedderAvailable ?? false }
        )

        let providers: [any AIProvider] = [
            AppleIntelligenceProvider(),
            WhisperKitProvider(),
            mlxChat,
            mlxEmbedder,
        ]
        let router = AIRouter(
            providers: providers,
            consent: consent,
            quota: quota,
            secrets: KeychainSecretStore()
        )
        let memoryGuard = MLXMemoryGuard(lifecycle: lifecycle)

        #if canImport(Vision)
        return AIGraph(
            router: router,
            mlxLifecycle: lifecycle,
            mlxMemoryGuard: memoryGuard,
            ocrPipeline: OCRPipeline()
        )
        #else
        return AIGraph(
            router: router,
            mlxLifecycle: lifecycle,
            mlxMemoryGuard: memoryGuard
        )
        #endif
    }
}
