import Foundation
import Testing

@testable import NexusMCPSidecar

@Suite("SidecarErrors")
struct SidecarErrorsTests {
    @Test("translates NSError code to MCP error code")
    func nsErrorMapping() {
        let error = NSError(
            domain: "com.kacperpietrzyk.nexus.agent",
            code: -32_003,
            userInfo: [
                NSLocalizedDescriptionKey: "task xyz not found",
                "agent.error.name": "not_found",
            ]
        )

        let mcp = SidecarErrors.from(nsError: error)

        #expect(mcp.code == -32_003)
        #expect(mcp.message.contains("not found"))
    }

    @Test("appNotRunning error is well-formed")
    func appNotRunning() {
        let error = SidecarErrors.appNotRunning

        #expect(error.code == -32_001)
        #expect(error.message.lowercased().contains("nexus"))
    }
}
