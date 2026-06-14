import Foundation
import NexusAI
import Testing
@testable import NexusAgent

@MainActor
@Suite struct MeetingDecomposeSpikeTests {
    // Manual: requires the real per-platform Gemma model downloaded on-device.
    // Run with: swift test --filter MeetingDecomposeSpikeTests after enabling.
    @Test(.disabled("manual: requires real on-device MLX model + network; see plan §9"))
    func spikeRealModelDecomposesPolishSummaries() async throws {
        // Caller wires a real router + assembler here during the manual run.
        // Measures: valid-JSON-first-try, valid-after-retry, latency, peak memory.
        // No assertions — this is a measurement harness, not a gate.
    }
}
