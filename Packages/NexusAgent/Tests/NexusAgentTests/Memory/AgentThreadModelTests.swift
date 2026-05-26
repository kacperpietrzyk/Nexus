import Foundation
import SwiftData
import Testing

@testable import NexusAgent

@Test func agentThreadDefaults() {
    let thread = AgentThread()
    #expect(!thread.id.uuidString.isEmpty)
    #expect(thread.title.isEmpty)
    #expect(thread.archivedAt == nil)
    #expect(thread.modelHint == nil)
    #expect(abs(thread.createdAt.timeIntervalSinceNow) < 1.0)
    #expect(abs(thread.updatedAt.timeIntervalSinceNow) < 1.0)
}

@Test func agentThreadProjectPinning() {
    let projectID = UUID()
    let thread = AgentThread(title: "Konferencja", projectID: projectID)
    #expect(thread.projectID == projectID)
}
