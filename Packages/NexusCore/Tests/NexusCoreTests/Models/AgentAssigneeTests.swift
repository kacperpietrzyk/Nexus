import Foundation
import Testing

@testable import NexusCore

@Suite("AgentAssignee")
struct AgentAssigneeTests {
    @Test("raw values are stable")
    func rawValues() {
        #expect(AgentAssignee.codex.rawValue == "codex")
        #expect(AgentAssignee.claude.rawValue == "claude")
    }

    @Test("Codable round-trips")
    func codable() throws {
        for assignee in AgentAssignee.allCases {
            let encoded = try JSONEncoder().encode(assignee)
            let decoded = try JSONDecoder().decode(AgentAssignee.self, from: encoded)
            #expect(decoded == assignee)
        }
    }

    @MainActor
    @Test("TaskItem agent accessor reflects assignedAgent; nil = self")
    func taskAccessor() {
        let plain = TaskItem(title: "x")
        #expect(plain.assignedAgent == nil)
        #expect(plain.agent == nil)

        let assigned = TaskItem(title: "y", assignedAgent: .codex)
        #expect(assigned.assignedAgent == "codex")
        #expect(assigned.agent == .codex)

        assigned.assignedAgent = "not-a-real-agent"
        #expect(assigned.agent == nil)
    }
}
