import Foundation
import NexusCore  // ModelManifest lives here (option-B relocation)
import NexusSync  // NexusModelContainer.makeInMemory()
import SwiftData
import Testing

@testable import NexusAI

// NOTE: Task 11 (2026-06-14) — catalog updated to 2 Gemma chat entries only.
// All assertions updated from Qwen counts/IDs to Gemma equivalents.

@MainActor
@Test func defaultCatalogParsesFromBundle() throws {
    let catalog = try ModelCatalog.loadDefault()
    #expect(catalog.version == 1)
    #expect(catalog.chat.count >= 2)
    #expect(catalog.embedders.count >= 1)

    let gemma26b = catalog.chat.first { $0.id == "gemma-4-26b-a4b" }
    #expect(gemma26b != nil)
    #expect(gemma26b?.hfPath == "mlx-community/gemma-4-26B-A4B-it-qat-4bit")
    #expect(gemma26b?.family == "gemma4")
    #expect(gemma26b?.sizeGB == 14.6)
    #expect(gemma26b?.recommendedRAMGB == 32)
    #expect(gemma26b?.supportsTools == true)

    // Regression guard: no qwen2.5 family, no capital-I "Instruct" in hfPath.
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
    #expect(manifests.count >= 3)  // 2 Gemma chat + 1 embedder
    #expect(manifests.contains { $0.id == "gemma-4-26b-a4b" })
    #expect(manifests.contains { $0.id == "gemma-4-e4b" })
    #expect(manifests.contains { $0.id == "multilingual-e5-large" })
}

/// Upgrade path: when an app update swaps the model lineup (Qwen → Gemma),
/// re-seeding must REMOVE catalog rows that are no longer in `DefaultCatalog.json`,
/// not just insert the new ones. Without pruning, a user who seeded the old
/// lineup would see both sets stacked in Manage Models.
@MainActor
@Test func bootstrapSeedPrunesEntriesAbsentFromCatalog() throws {
    let container = try NexusModelContainer.makeInMemory()
    let ctx = ModelContext(container)
    ctx.insert(
        ModelManifest(
            id: "qwen2.5-7b-instruct-4bit",
            hfPath: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            family: "qwen2.5",
            displayName: "Qwen 2.5 7B",
            sizeGB: 4.3,
            recommendedRAMGB: 16,
            contextLength: 32_768,
            supportsTools: true,
            supportsVision: false,
            supportedLocales: ["en"],
            purpose: "chat"
        )
    )
    try ctx.save()

    try ModelCatalog.bootstrap.seed(into: ctx)

    let manifests = try ctx.fetch(FetchDescriptor<ModelManifest>())
    let ids = Set(manifests.map(\.id))
    #expect(
        !ids.contains("qwen2.5-7b-instruct-4bit"),
        "A row absent from DefaultCatalog.json must be pruned on re-seed.")
    #expect(
        manifests.filter { $0.purpose == "chat" }.count == 2,
        "Exactly the 2 Gemma chat entries should remain.")
    #expect(ids.contains("gemma-4-e4b"))
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
/// updating `ModelCatalog.defaultEmbedderID`, this fails.
@MainActor
@Test func defaultEmbedderIDMatchesACatalogEntry() throws {
    let catalog = try ModelCatalog.loadDefault()
    #expect(
        catalog.embedders.contains { $0.id == ModelCatalog.defaultEmbedderID },
        "ModelCatalog.defaultEmbedderID must match an embedders[].id in DefaultCatalog.json")
}
