import Foundation
import NexusSync
import Testing

@testable import NexusAI

@Test func aiGraphRouterRejectsUnsupportedLongContextCapability() async throws {
    let container = try NexusModelContainer.makeInMemory()
    let graph = AIComposition.makeGraph(container: container)

    await #expect(throws: AIRouterError.capabilityNotSupported(.longContext)) {
        try await graph.router.route(
            AIRequest(
                prompt: "summarize meeting",
                capability: .longContext,
                connectivity: .cloudAllowed
            )
        )
    }
}

@Test func aiGraphMLXProvidersUnavailableWithoutDownloadedModels() async throws {
    let container = try NexusModelContainer.makeInMemory()
    let graph = AIComposition.makeGraph(container: container)

    // Fresh lifecycle: both model slots are `.empty`, so the MLX chat and
    // embedder providers must report unavailable. This is deterministic and
    // offline — no model load, no network.
    #expect(graph.mlxLifecycle.isChatAvailable == false)
    #expect(graph.mlxLifecycle.isEmbedderAvailable == false)
}
