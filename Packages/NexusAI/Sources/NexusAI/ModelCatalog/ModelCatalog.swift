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

    /// Reads and decodes `DefaultCatalog.json` from `Bundle.module`.
    ///
    /// - Parameter bundle: Override for testing; pass `nil` to use the NexusAI module bundle.
    public static func loadDefault(bundle: Bundle? = nil) throws -> CatalogDoc {
        let resolvedBundle = bundle ?? .module
        guard let url = resolvedBundle.url(forResource: "DefaultCatalog", withExtension: "json") else {
            throw LoadError.resourceMissing("DefaultCatalog.json")
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(CatalogDoc.self, from: data)
        } catch {
            throw LoadError.decodeFailed(String(describing: error))
        }
    }

    // MARK: - Seeder

    // swiftlint:disable type_name
    /// Namespace for idempotent catalog seeding into a SwiftData context.
    public enum bootstrap {  // lowercase intentional: mirrors Swift stdlib namespace style
        /// Inserts any catalog entry whose `id` is not already present in the store.
        ///
        /// Uses a `Set<String>` membership check instead of `@Attribute(.unique)`,
        /// which is incompatible with CloudKit (established Phase 1a convention).
        /// Safe to call multiple times — existing rows are never touched.
        ///
        /// `@MainActor`: `ModelContext` is `@MainActor`-isolated under Swift 6
        /// strict concurrency; the seed mutates it, so the call site (Task 14
        /// composition root) must hop to the main actor.
        @MainActor
        public static func seed(into context: ModelContext) throws {
            let catalog = try ModelCatalog.loadDefault()
            let existing = try context.fetch(FetchDescriptor<ModelManifest>())
            let existingIDs = Set(existing.map(\.id))

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
