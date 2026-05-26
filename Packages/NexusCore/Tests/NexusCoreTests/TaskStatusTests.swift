import Foundation
import Testing

@testable import NexusCore

@Suite("TaskStatus")
struct TaskStatusTests {
    @Test("raw values are stable")
    func rawValues() {
        #expect(TaskStatus.open.rawValue == "open")
        #expect(TaskStatus.done.rawValue == "done")
        #expect(TaskStatus.snoozed.rawValue == "snoozed")
    }

    @Test("Codable round-trips")
    func codable() throws {
        let encoded = try JSONEncoder().encode(TaskStatus.snoozed)
        let decoded = try JSONDecoder().decode(TaskStatus.self, from: encoded)
        #expect(decoded == .snoozed)
    }
}
