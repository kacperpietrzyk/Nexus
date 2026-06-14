import Foundation
import NexusAI

/// Narrow inference seam so SkillRunner is testable without the concrete AIRouter actor.
public protocol SkillInference: Sendable {
    func generate(_ request: AIRequest) async throws -> AIResponse
}

/// Production adapter over the existing router.
public struct RouterSkillInference: SkillInference {
    private let router: AIRouter
    public init(router: AIRouter) { self.router = router }
    public func generate(_ request: AIRequest) async throws -> AIResponse {
        try await router.route(request)
    }
}
