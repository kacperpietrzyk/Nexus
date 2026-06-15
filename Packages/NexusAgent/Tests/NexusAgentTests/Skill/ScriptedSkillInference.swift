import Foundation
import NexusAI

@testable import NexusAgent

final class ScriptedSkillInference: SkillInference, @unchecked Sendable {
    private var responses: [String]
    private(set) var requests: [AIRequest] = []
    init(responses: [String]) { self.responses = responses }
    func generate(_ request: AIRequest) async throws -> AIResponse {
        requests.append(request)
        let text = responses.isEmpty ? "" : responses.removeFirst()
        return AIResponse(text: text, providerUsed: .mlx)
    }
}
