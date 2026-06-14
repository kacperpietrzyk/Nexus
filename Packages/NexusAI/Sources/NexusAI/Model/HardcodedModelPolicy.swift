import Foundation

/// Resolves the single per-platform model set from the catalog + tier.
/// Protocol allows injection of a test double if needed.
public protocol HardcodedModelPolicy: Sendable {
    func resolve() -> ResolvedModelSet
}

/// Resolves the single per-platform chat model + the fixed embedder from the catalog,
/// using TierDetector's per-platform recommendation. No user picker.
public struct DefaultHardcodedModelPolicy: HardcodedModelPolicy {
    private let catalog: ModelCatalog.CatalogDoc
    private let tier: DeviceTier

    public init(catalog: ModelCatalog.CatalogDoc, tier: DeviceTier = TierDetector.detectCurrent()) {
        self.catalog = catalog
        self.tier = tier
    }

    public func resolve() -> ResolvedModelSet {
        let chat = catalog.chat.first { $0.id == tier.recommendedChat } ?? catalog.chat.first!
        let embedderID = tier.recommendedEmbedder ?? ModelCatalog.defaultEmbedderID
        let embedder = catalog.embedders.first { $0.id == embedderID } ?? catalog.embedders.first!
        return ResolvedModelSet(
            chatManifestID: chat.id,
            chatHFPath: chat.hfPath,
            chatContextLength: chat.contextLength,
            chatSizeGB: chat.sizeGB,
            embedderManifestID: embedder.id,
            embedderHFPath: embedder.hfPath,
            embedderSizeGB: embedder.sizeGB
        )
    }
}
