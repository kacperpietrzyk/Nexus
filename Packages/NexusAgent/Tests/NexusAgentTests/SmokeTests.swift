import Testing

@testable import NexusAgent

@Test func packageLoads() {
    #expect(NexusAgentInfo.identifier == "com.kacperpietrzyk.nexus.agent")
}
