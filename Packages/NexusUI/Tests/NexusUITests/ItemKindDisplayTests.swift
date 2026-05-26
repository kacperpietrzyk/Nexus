import NexusCore
import Testing

@testable import NexusUI

@Test func itemKindDisplayName_capitalizesEachKind() {
    #expect(ItemKind.note.displayName == "Note")
    #expect(ItemKind.task.displayName == "Task")
    #expect(ItemKind.meeting.displayName == "Meeting")
    #expect(ItemKind.project.displayName == "Project")
    #expect(ItemKind.section.displayName == "Section")
    #expect(ItemKind.savedFilter.displayName == "Saved Filter")
    #expect(ItemKind.debug.displayName == "Debug")
}
