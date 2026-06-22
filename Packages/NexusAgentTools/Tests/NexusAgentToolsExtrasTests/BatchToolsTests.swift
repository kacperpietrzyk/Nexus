import Foundation
import NexusAgentTools
import NexusCore
import Testing

@testable import NexusAgentToolsExtras

@MainActor
@Suite("batch.begin / batch.end tools")
struct BatchToolsTests {

    @Test("names follow the namespace.action lowercase convention")
    func nameConvention() {
        for name in [BatchBeginTool().name, BatchEndTool().name] {
            let parts = name.split(separator: ".", omittingEmptySubsequences: false)
            #expect(parts.count == 2)
            #expect(parts.first == "batch")
            #expect(name.allSatisfy { $0.isLowercase || $0 == "." })
        }
    }

    @Test("both tools carry non-empty metadata and an object input schema")
    func metadataAndSchema() throws {
        for tool in [BatchBeginTool() as any AgentTool, BatchEndTool()] {
            #expect(!tool.name.isEmpty)
            #expect(!tool.description.isEmpty)
            let data = try JSONEncoder().encode(tool.inputSchema)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect((json?["type"] as? String) == "object")
        }
    }

    @Test("begin then end reports a resume; surplus end is a no-op")
    func beginEndBehavior() async throws {
        // Drive a private coordinator instance to keep the shared one untouched.
        var resumes = 0
        let coordinator = RefreshSuspensionCoordinator(
            expiryInterval: 60,
            clock: { Date() },
            onResume: { resumes += 1 }
        )

        #expect(coordinator.isSuspended == false)
        coordinator.begin()
        #expect(coordinator.isSuspended == true)
        #expect(coordinator.end() == true)
        #expect(resumes == 1)
        #expect(coordinator.end() == false)
        #expect(resumes == 1)
    }
}
