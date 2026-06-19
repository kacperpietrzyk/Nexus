#if os(macOS)
import Testing
import Foundation
import NexusCore
@testable import NexusMeetings

@Suite struct RelatedChipsTests {
    private func item(_ kind: ItemKind, _ t: String) -> LiquidMeetingsModel.LinkedItem {
        .init(id: UUID(), kind: kind, targetID: UUID(), title: t, isBacklink: false)
    }

    @Test func excludesPersonsAndGroupsByKind() {
        let items = [item(.task, "A"), item(.person, "Ada"), item(.note, "N"), item(.task, "B")]
        let groups = RelatedChips.groups(items)
        #expect(!groups.contains { $0.kind == ItemKind.person })
        let tasks = groups.first { $0.kind == ItemKind.task }
        #expect(tasks?.items.count == 2)
        #expect(groups.first?.kind == ItemKind.task)  // task before note in display order
    }
}
#endif
