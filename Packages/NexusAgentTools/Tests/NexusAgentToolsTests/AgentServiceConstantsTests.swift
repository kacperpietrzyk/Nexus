import Foundation
import NexusAgentTools
import Testing

struct AgentServiceConstantsTests {
    @Test
    func exposesExpectedConstantValues() {
        #expect(AgentServiceConstants.appGroupIdentifier == "group.com.kacperpietrzyk.Nexus")
        #expect(AgentServiceConstants.socketFileName == "agent.sock")
        #expect(AgentServiceConstants.protocolVersion == "1.0")
        #expect(AgentServiceConstants.mcpEnabledKey == "nexus.mcp.enabled")
    }

    @Test
    func socketPathStaysWithinSunPathLimit() throws {
        let url = try #require(AgentServiceConstants.socketURL())
        #expect(url.path.utf8.count < 104)
        #expect(url.lastPathComponent == "agent.sock")
    }
}
