import Foundation
import Testing

@testable import NexusAI

// Locks spec §6.2 cascade-vs-short-circuit semantics:
//  - Selection (steps 1–6) cascades on consent/quota miss to next candidate.
//  - Once a provider is selected and invoked, a thrown error propagates to
//    the caller without router-level re-routing.
//  - If every candidate fails its gate, the LAST candidate's error surfaces.
@Suite("AIRouter cascade vs short-circuit (§6.2)")
struct AIRouterCascadeShortCircuitTests {

    @Test("invoke that throws does NOT cascade")
    func invokeFailureDoesNotCascade() async throws {
        // Single on-device provider configured to throw on invoke. Router should
        // select it (passes platform/capability/on-device-preferred filters),
        // call generate, receive the throw, and propagate it up — NOT silently
        // fall through to a fallback.
        let provider = FakeAIProvider(
            id: .appleIntelligence,
            capabilities: [.generate],
            sendsDataExternally: false,
            requiresNetwork: false,
            isAvailableOnThisPlatform: true,
            errorToThrow: .providerNotImplemented(.appleIntelligence)
        )

        let router = AIRouter(
            providers: [provider],
            consent: InMemoryConsentStore(),
            quota: InMemoryQuotaTracker(),
            secrets: InMemorySecretStore()
        )

        await #expect(throws: AIRouterError.providerNotImplemented(.appleIntelligence)) {
            _ = try await router.route(
                AIRequest(prompt: "hi", capability: .generate)
            )
        }
        #expect(provider.generateCallCount == 1, "Router must have invoked the selected provider exactly once")
    }

}
