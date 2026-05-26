import Foundation
import SwiftData
import Testing

@testable import NexusCore

@MainActor
private func makeInMemoryContext() throws -> ModelContext {
    let schema = Schema([ModelManifest.self])
    let container = try ModelContainer(
        for: schema,
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ModelContext(container)
}

@MainActor
@Test func modelManifestRoundTripsCoreFields() throws {
    let ctx = try makeInMemoryContext()

    let manifest = ModelManifest(
        id: "qwen3.5-9b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-9B-Instruct-4bit",
        family: "qwen3.5",
        displayName: "Qwen 3.5 9B",
        sizeGB: 5.8,
        recommendedRAMGB: 32,
        contextLength: 32_768,
        supportsTools: true,
        supportsVision: false,
        supportedLocales: ["en", "pl"],
        purpose: "chat"
    )
    ctx.insert(manifest)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<ModelManifest>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.id == "qwen3.5-9b-instruct-4bit")
    #expect(fetched.first?.contextLength == 32_768)
    #expect(fetched.first?.purpose == "chat")
}

@MainActor
@Test func modelManifestUserPreferenceOverridesRoundTripAsNil() throws {
    let ctx = try makeInMemoryContext()

    let manifest = ModelManifest(
        id: "qwen3.5-4b-instruct-4bit",
        hfPath: "mlx-community/Qwen3.5-4B-Instruct-4bit",
        family: "qwen3.5",
        displayName: "Qwen 3.5 4B",
        sizeGB: 3.2,
        recommendedRAMGB: 16,
        contextLength: 16_384,
        supportsTools: true,
        supportsVision: false,
        supportedLocales: ["en", "pl"],
        purpose: "chat"
    )
    ctx.insert(manifest)
    try ctx.save()

    // Assert from the FETCHED instance: this verifies SwiftData actually
    // persists and round-trips `nil` for the nullable override columns,
    // not merely that the Swift default arguments propagated in memory.
    let fetched = try ctx.fetch(FetchDescriptor<ModelManifest>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.temperatureOverride == nil)
    #expect(fetched.first?.maxTokensOverride == nil)
    #expect(fetched.first?.idleTimeoutSecondsOverride == nil)
    #expect(fetched.first?.systemPromptOverride == nil)
}
