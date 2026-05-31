import Foundation
import NexusCore  // ModelManifest lives here (option-B relocation)
import NexusSync  // NexusModelContainer.makeInMemory()
import SwiftData
import Testing

@testable import NexusAI

@MainActor
@Test func defaultCatalogParsesFromBundle() throws {
    let catalog = try ModelCatalog.loadDefault()
    #expect(catalog.version == 1)
    #expect(catalog.chat.count >= 4)
    #expect(catalog.embedders.count >= 1)

    let qwen9b = catalog.chat.first { $0.id == "qwen3.5-9b-4bit" }
    #expect(qwen9b != nil)
    #expect(qwen9b?.hfPath == "mlx-community/Qwen3.5-9B-4bit")
    #expect(qwen9b?.family == "qwen3.5")
    #expect(qwen9b?.sizeGB == 6.0)
    #expect(qwen9b?.recommendedRAMGB == 16)
    #expect(qwen9b?.supportsTools == true)

    // Regression guard: the fictional `Qwen3.5-*-Instruct-4bit` repos (HTTP 401)
    // that PR #15 wrongly "fixed" by downgrading the whole family to Qwen2.5 must
    // not return. The real Qwen3.5 repos drop the `-Instruct` suffix and use the
    // 4B/9B/27B size lineup; Qwen2.5 must be fully gone from the catalog.
    #expect(!catalog.chat.contains { $0.family == "qwen2.5" })
    #expect(!catalog.chat.contains { $0.hfPath.contains("Instruct") })
}

@MainActor
@Test func bootstrapSeedInsertsEveryCatalogEntry() throws {
    // Production-equivalent in-memory container (2-config synced + local-only,
    // NexusSchemaV7 baseline includes ModelManifest/ModelDownloadEvent).
    let container = try NexusModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    try ModelCatalog.bootstrap.seed(into: ctx)
    let manifests = try ctx.fetch(FetchDescriptor<ModelManifest>())
    #expect(manifests.count >= 5)  // 4 chat + 1 embedder
    #expect(manifests.contains { $0.id == "qwen3.5-27b-4bit" })
    #expect(manifests.contains { $0.id == "gemma-4-e4b-it-4bit" })
    #expect(manifests.contains { $0.id == "multilingual-e5-large" })
}

@MainActor
@Test func bootstrapSeedIsIdempotent() throws {
    let container = try NexusModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    try ModelCatalog.bootstrap.seed(into: ctx)
    let firstCount = try ctx.fetchCount(FetchDescriptor<ModelManifest>())
    try ModelCatalog.bootstrap.seed(into: ctx)
    let secondCount = try ctx.fetchCount(FetchDescriptor<ModelManifest>())
    #expect(firstCount == secondCount, "Re-seed must not duplicate rows.")
}

/// Single-source enforcement (LabKit 1l#3): the fallback embedder ID used by
/// `MLXLifecycleController.embedderFolderURL()` / `TierDetector` must stay a
/// real catalog entry. If `DefaultCatalog.json` renames the embedder without
/// updating `ModelCatalog.defaultEmbedderID`, this fails — that is the whole
/// point of replacing the bare string literal.
@MainActor
@Test func defaultEmbedderIDMatchesACatalogEntry() throws {
    let catalog = try ModelCatalog.loadDefault()
    #expect(
        catalog.embedders.contains { $0.id == ModelCatalog.defaultEmbedderID },
        "ModelCatalog.defaultEmbedderID must match an embedders[].id in DefaultCatalog.json")
}
