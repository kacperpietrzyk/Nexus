import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NexusAgent

@Test func agentMemoryEntryDefaults() {
    let entry = AgentMemoryEntry(
        scope: "global",
        key: "prefers-morning-briefs",
        content: "User prefers briefs before 9am"
    )
    #expect(entry.kind == .agentMemory)
    #expect(entry.scope == "global")
    #expect(entry.confidence == 1.0)
    #expect(entry.source == .agent)
}

@Test func agentMemoryEntrySearchableText() {
    let entry = AgentMemoryEntry(
        scope: "project:abc",
        key: "deadline-known",
        content: "Konferencja deadline 2026-05-21"
    )
    #expect(entry.searchableText.contains("project:abc"))
    #expect(entry.searchableText.contains("deadline-known"))
    #expect(entry.searchableText.contains("2026-05-21"))
}
