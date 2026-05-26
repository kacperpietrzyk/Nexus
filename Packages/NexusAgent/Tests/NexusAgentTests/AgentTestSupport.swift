import Foundation
import SwiftData

@testable import NexusAgent

enum AgentTestSupport {
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([
                AgentThread.self,
                AgentMessage.self,
                AgentMemoryEntry.self,
                AgentAuditLog.self,
                AgentSchedule.self,
                ItemEmbedding.self,
            ]),
            configurations: [.init(isStoredInMemoryOnly: true)]
        )
    }

    static func makeContext() throws -> ModelContext {
        try ModelContext(makeContainer())
    }
}
