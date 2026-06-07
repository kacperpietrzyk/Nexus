import Foundation
import Testing

@testable import NexusCore

@Test func itemKind_rawValues_areStableLowercaseStrings() {
    #expect(ItemKind.note.rawValue == "note")
    #expect(ItemKind.task.rawValue == "task")
    #expect(ItemKind.meeting.rawValue == "meeting")
    #expect(ItemKind.project.rawValue == "project")
    #expect(ItemKind.section.rawValue == "section")
    #expect(ItemKind.savedFilter.rawValue == "savedFilter")
    #expect(ItemKind.debug.rawValue == "debug")
    #expect(ItemKind.agentMemory.rawValue == "agentMemory")
    #expect(ItemKind.scheduledBlock.rawValue == "scheduledBlock")
}

@Test func itemKind_isCodable() throws {
    let items: [ItemKind] = [.note, .task, .meeting, .project, .section, .savedFilter, .debug, .agentMemory, .scheduledBlock]
    let encoded = try JSONEncoder().encode(items)
    let decoded = try JSONDecoder().decode([ItemKind].self, from: encoded)
    #expect(
        decoded == [
            ItemKind.note, .task, .meeting, .project, .section, .savedFilter, .debug, .agentMemory, .scheduledBlock,
        ]
    )
}

@Test func itemKind_allCases_haveStableOrder() {
    let expected: [ItemKind] = [.note, .task, .meeting, .project, .section, .savedFilter, .debug, .agentMemory, .scheduledBlock]
    #expect(ItemKind.allCases == expected)
}

@Test func agentMemoryCaseExists() {
    let kind = ItemKind.agentMemory
    #expect(kind.rawValue == "agentMemory")
}

@Test func agentMemoryDisplayName() {
    #expect(ItemKind.agentMemory.displayName == "Agent Memory")
}

@Test func scheduledBlockCaseExists() {
    #expect(ItemKind.scheduledBlock.rawValue == "scheduledBlock")
}

@Test func scheduledBlockDisplayName() {
    #expect(ItemKind.scheduledBlock.displayName == "Scheduled Block")
}

@Test func allItemKindsExhaustive() {
    let all: [ItemKind] = [.note, .task, .meeting, .project, .section, .savedFilter, .debug, .agentMemory, .scheduledBlock]
    #expect(Set(ItemKind.allCases) == Set(all))
}
