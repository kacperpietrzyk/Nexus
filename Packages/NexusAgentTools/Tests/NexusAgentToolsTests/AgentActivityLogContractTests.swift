import Foundation
import Testing

@testable import NexusAgentTools

@Suite("AgentActivityLog")
struct AgentActivityLogContractTests {
    @MainActor
    @Test("records entries in order")
    func basic() {
        let log = AgentActivityLog()

        log.record(.success(name: "tasks.list", argsRedacted: "{}", durationMs: 12))
        log.record(.success(name: "tasks.get", argsRedacted: "{}", durationMs: 5))

        #expect(log.entries.count == 2)
        #expect(log.entries[0].toolName == "tasks.list")
        #expect(log.entries[1].toolName == "tasks.get")
    }

    @MainActor
    @Test("rotates when exceeding maxEntries")
    func rotation() {
        let log = AgentActivityLog()

        for index in 0..<(AgentActivityLog.maxEntries + 50) {
            log.record(.success(name: "tasks.\(index)", argsRedacted: "{}", durationMs: 1))
        }

        #expect(log.entries.count == AgentActivityLog.maxEntries)
        #expect(log.entries.first?.toolName == "tasks.50")
    }

    @MainActor
    @Test("failure entries record JSON-RPC code")
    func failure() {
        let log = AgentActivityLog()

        log.record(.failure(name: "tasks.delete", argsRedacted: "{}", code: -32_003, durationMs: 7))

        #expect(log.entries.first?.resultStatus == .errorCode(-32_003))
    }

    @MainActor
    @Test("clear empties the log")
    func clear() {
        let log = AgentActivityLog()

        log.record(.success(name: "tasks.list", argsRedacted: "{}", durationMs: 1))
        log.clear()

        #expect(log.entries.isEmpty)
    }
}
