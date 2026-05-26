import Foundation
import SwiftData
import Testing

@testable import NexusAgent

@Test func agentMessageDefaults() {
    let m = AgentMessage(threadID: UUID(), role: .user, content: "hi")
    #expect(m.role == .user)
    #expect(m.content == "hi")
    #expect(m.tokensIn == 0)
    #expect(m.tokensOut == 0)
    #expect(!m.redactedContent)
    #expect(m.toolCallJSON == nil)
}

@Test func agentMessageRoleSerialization() {
    for role in AgentMessageRole.allCases {
        #expect(AgentMessageRole(rawValue: role.rawValue) == role)
    }
}
