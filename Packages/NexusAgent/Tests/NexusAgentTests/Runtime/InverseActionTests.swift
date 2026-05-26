import Foundation
import Testing

@testable import NexusAgent

@Test func inverseActionRoundTrip() throws {
    let payload = Data(#"{"taskID":"x"}"#.utf8)
    let action = InverseAction(toolName: "tasks.unsnooze", inputJSON: payload)
    let encoded = try JSONEncoder().encode(action)
    let decoded = try JSONDecoder().decode(InverseAction.self, from: encoded)
    #expect(decoded.toolName == "tasks.unsnooze")
    #expect(decoded.inputJSON == payload)
}
