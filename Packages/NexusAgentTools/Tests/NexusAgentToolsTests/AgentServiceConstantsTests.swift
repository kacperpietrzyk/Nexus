import Foundation
import NexusAgentTools
import Testing

struct AgentServiceConstantsTests {
    @Test
    func exposesExpectedConstantValues() {
        #expect(AgentServiceConstants.machServiceSuffix == "com.kacperpietrzyk.nexus.agent")
        #expect(AgentServiceConstants.protocolVersion == "1.0")
        #expect(AgentServiceConstants.mcpEnabledKey == "nexus.mcp.enabled")
    }

    @Test
    func buildsMachServiceNameFromBundleTeamIdentifierPrefix() {
        let bundle = BundleMock(teamIdentifierPrefix: "TEAMID.")

        #expect(
            AgentServiceConstants.machServiceName(from: bundle)
                == "TEAMID.com.kacperpietrzyk.nexus.agent"
        )
        #expect(machServiceName(from: bundle) == AgentServiceConstants.machServiceName(from: bundle))
    }
}

private final class BundleMock: Bundle, @unchecked Sendable {
    private let teamIdentifierPrefix: String?

    init(teamIdentifierPrefix: String?) {
        self.teamIdentifierPrefix = teamIdentifierPrefix
        super.init()
    }

    override var infoDictionary: [String: Any]? {
        guard let teamIdentifierPrefix else { return [:] }
        return ["TeamIdentifierPrefix": teamIdentifierPrefix]
    }
}
