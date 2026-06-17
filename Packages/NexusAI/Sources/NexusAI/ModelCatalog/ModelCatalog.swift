import Foundation
import NexusCore
import SwiftData

/// Loads the bundled ``DefaultCatalog.json`` and seeds ``ModelManifest`` rows
/// into a SwiftData context idempotently.
///
/// Seeding is invoked from the composition root at app launch (Task 14) — it is
/// NOT called from `didMigrate` (NexusSync cannot import NexusAI without a
/// package cycle).
public enum ModelCatalog {
    // MARK: - Canonical defaults

    /// The canonical embedder manifest ID used as the fallback when no
    /// embedder assignment is recorded yet (the only supported embedder as of
    /// Phase 1l). Single source of truth for what was previously a bare
    /// `"multilingual-e5-large"` string literal duplicated across
    /// `MLXLifecycleController` and `TierDetector` (LabKit 1l#3 — kills the
    /// fallback-by-coincidence). MUST match the `embedders[].id` in
    /// `DefaultCatalog.json`; `ModelCatalogDefaultsTests` asserts that.
    public static let defaultEmbedderID = "multilingual-e5-large"

    // MARK: - JSON DTO

    /// Top-level structure of `DefaultCatalog.json`.
    public struct CatalogDoc: Decodable, Sendable {
        public let version: Int
        public let lastUpdated: String
        public let chat: [Entry]
        public let embedders: [Entry]
    }

    /// One model entry inside the catalog JSON.
    public struct Entry: Decodable, Sendable {
        public let id: String
        public let hfPath: String
        public let family: String
        public let displayName: String
        public let sizeGB: Double
        public let recommendedRAMGB: Int
        public let contextLength: Int
        public let supportsTools: Bool
        public let supportsVision: Bool
        public let supportedLocales: [String]
    }

    // MARK: - Errors

    public enum LoadError: Error, Sendable {
        case resourceMissing(String)
        case decodeFailed(String)
    }

    // MARK: - Loader

    /// Memoization for the default (`Bundle.module`) catalog. The bundled
    /// `DefaultCatalog.json` is immutable for the process lifetime, so the
    /// decoded value can be cached and shared. `loadDefault()` is called per
    /// brief-readiness probe (many times/min on the main actor); without this it
    /// re-runs `Data(contentsOf:)` + `JSONDecoder().decode` on every call.
    ///
    /// Only the `bundle == nil` path is cached — an explicit test bundle bypasses
    /// the cache entirely so test-injected resources are never served stale.
    /// `NSLock`-guarded for thread safety; `CatalogDoc` is `Sendable`.
    private static let defaultCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedDefault: CatalogDoc?

    /// Reads and decodes `DefaultCatalog.json` from `Bundle.module`.
    ///
    /// The default (`bundle == nil`) result is memoized after the first decode;
    /// repeat calls return the same value without re-reading the bundle.
    ///
    /// - Parameter bundle: Override for testing; pass `nil` to use the NexusAI module bundle.
    public static func loadDefault(bundle: Bundle? = nil) throws -> CatalogDoc {
        if bundle == nil {
            defaultCacheLock.lock()
            if let cached = cachedDefault {
                defaultCacheLock.unlock()
                return cached
            }
            defaultCacheLock.unlock()
        }

        let resolvedBundle = bundle ?? .module
        guard let url = resolvedBundle.url(forResource: "DefaultCatalog", withExtension: "json") else {
            throw LoadError.resourceMissing("DefaultCatalog.json")
        }
        let data = try Data(contentsOf: url)
        let decoded: CatalogDoc
        do {
            decoded = try JSONDecoder().decode(CatalogDoc.self, from: data)
        } catch {
            throw LoadError.decodeFailed(String(describing: error))
        }

        if bundle == nil {
            defaultCacheLock.lock()
            cachedDefault = decoded
            defaultCacheLock.unlock()
        }
        return decoded
    }

    // MARK: - Seeder

    // swiftlint:disable type_name
    /// Namespace for idempotent catalog seeding into a SwiftData context.
    public enum bootstrap {  // lowercase intentional: mirrors Swift stdlib namespace style
        /// Reconciles the store with the bundled catalog: inserts entries whose
        /// `id` is new and removes rows whose `id` is no longer in the catalog.
        ///
        /// Uses a `Set<String>` membership check instead of `@Attribute(.unique)`,
        /// which is incompatible with CloudKit (established Phase 1a convention).
        /// Idempotent — re-seeding the same catalog is a no-op.
        ///
        /// **Pruning** is what makes an app update that swaps the model lineup
        /// (e.g. Qwen2.5 → Qwen3.5) clean: without it the old IDs would linger
        /// next to the new ones and show as phantom extras in Manage Models.
        /// `ModelManifest` is local-only and carries no per-device state (download
        /// status / assignment live in the `UserDefaults`-backed
        /// ``ModelManifestLocalState``, keyed by id), so deleting a row only
        /// removes it from the catalog list — it does not touch any in-flight or
        /// downloaded state, and a stale `UserDefaults`/on-disk remnant of a
        /// removed model is inert.
        ///
        /// `@MainActor`: `ModelContext` is `@MainActor`-isolated under Swift 6
        /// strict concurrency; the seed mutates it, so the call site (Task 14
        /// composition root) must hop to the main actor.
        @MainActor
        public static func seed(into context: ModelContext) throws {
            let catalog = try ModelCatalog.loadDefault()
            let existing = try context.fetch(FetchDescriptor<ModelManifest>())
            let existingIDs = Set(existing.map(\.id))
            let catalogIDs = Set(catalog.chat.map(\.id)).union(catalog.embedders.map(\.id))

            // Prune rows the catalog no longer defines (lineup swap on update).
            for manifest in existing where !catalogIDs.contains(manifest.id) {
                context.delete(manifest)
            }

            func upsert(_ entries: [Entry], purpose: String) {
                for entry in entries where !existingIDs.contains(entry.id) {
                    context.insert(
                        ModelManifest(
                            id: entry.id,
                            hfPath: entry.hfPath,
                            family: entry.family,
                            displayName: entry.displayName,
                            sizeGB: entry.sizeGB,
                            recommendedRAMGB: entry.recommendedRAMGB,
                            contextLength: entry.contextLength,
                            supportsTools: entry.supportsTools,
                            supportsVision: entry.supportsVision,
                            supportedLocales: entry.supportedLocales,
                            purpose: purpose
                        )
                    )
                }
            }

            upsert(catalog.chat, purpose: "chat")
            upsert(catalog.embedders, purpose: "embedder")
            try context.save()
        }
    }  // swiftlint:enable type_name
}
