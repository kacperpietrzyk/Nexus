// Packages/NexusAgent/Tests/NexusAgentTests/AgentInsightProjectorTests.swift
import Foundation
import InboxShell
import Testing

@testable import NexusAgent

@Suite struct AgentInsightProjectorTests {
    @Test func projectsOpenRecordsAsAgentRows() async throws {
        let id = UUID()
        let projector = AgentInsightProjector(openProvider: {
            [.init(id: id, title: "Plan your day", kind: "day_plan", createdAt: .init(timeIntervalSince1970: 5))]
        })
        let items = try await projector.project()
        #expect(items.count == 1)
        #expect(items.first?.key == "insight:\(id.uuidString)")
        #expect(items.first?.stream == .agent)
        #expect(items.first?.route == .agentInsight(id))
    }
}
