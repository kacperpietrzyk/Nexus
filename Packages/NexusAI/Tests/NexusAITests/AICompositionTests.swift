import Foundation
import NexusSync
import Testing

@testable import NexusAI

@Test func aiCompositionHasNoLongContextCloudProviderStub() async throws {
    let container = try NexusModelContainer.makeInMemory()
    let router = AIComposition.makeRouter(container: container)

    await #expect(throws: AIRouterError.capabilityNotSupported(.longContext)) {
        try await router.route(
            AIRequest(
                prompt: "summarize meeting",
                capability: .longContext,
                connectivity: .cloudAllowed
            )
        )
    }
}
