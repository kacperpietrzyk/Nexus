import Foundation
import Testing

@testable import NexusCore

@Suite("TaskPriority")
struct TaskPriorityTests {
    @Test("raw values and order are stable")
    func rawValues() {
        #expect(TaskPriority.allCases == [.none, .low, .medium, .high])
        #expect(TaskPriority.none.rawValue == 0)
        #expect(TaskPriority.high.rawValue == 3)
    }

    @Test("Codable round-trips")
    func codable() throws {
        let encoded = try JSONEncoder().encode(TaskPriority.medium)
        let decoded = try JSONDecoder().decode(TaskPriority.self, from: encoded)
        #expect(decoded == .medium)
    }
}
