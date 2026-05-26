import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func paletteAction_initializesWithRequiredFields() {
    let action = PaletteAction(id: "today.open", title: "Open Today") {}
    #expect(action.id == "today.open")
    #expect(action.title == "Open Today")
    #expect(action.subtitle == nil)
    #expect(action.shortcut.isEmpty)
}

@MainActor
@Test func paletteAction_withShortcutAndSubtitle() {
    let action = PaletteAction(
        id: "task.new",
        title: "New Task",
        subtitle: "Inbox",
        shortcut: ["⌘", "N"]
    ) {}
    #expect(action.shortcut == ["⌘", "N"])
    #expect(action.subtitle == "Inbox")
}

@MainActor
@Test func paletteFilter_emptyQuery_returnsAll() {
    let actions = sampleActions()
    let filtered = CommandPalette.filter(actions: actions, query: "")
    #expect(filtered.count == actions.count)
}

@MainActor
@Test func paletteFilter_caseInsensitivePrefix_matches() {
    let actions = sampleActions()
    let filtered = CommandPalette.filter(actions: actions, query: "open")
    #expect(filtered.count == 2)
    #expect(filtered.contains(where: { $0.id == "today.open" }))
    #expect(filtered.contains(where: { $0.id == "graph.open" }))
}

@MainActor
@Test func paletteFilter_substringMatch_works() {
    let actions = sampleActions()
    let filtered = CommandPalette.filter(actions: actions, query: "task")
    #expect(filtered.count == 1)
    #expect(filtered.first?.id == "task.new")
}

@MainActor
@Test func paletteFilter_noMatch_returnsEmpty() {
    let actions = sampleActions()
    let filtered = CommandPalette.filter(actions: actions, query: "zzzz")
    #expect(filtered.isEmpty)
}

@MainActor
@Test func commandPalette_initializesWithActions() {
    let palette = CommandPalette(actions: sampleActions())
    #expect(palette.actions.count == 3)
}

@MainActor
@Test func commandPalette_buildsEmptyV4Overlay() {
    let palette = CommandPalette(actions: [])
    #expect(palette.actions.isEmpty)
}

@MainActor
private func sampleActions() -> [PaletteAction] {
    [
        PaletteAction(id: "today.open", title: "Open Today") {},
        PaletteAction(id: "graph.open", title: "Open Graph") {},
        PaletteAction(id: "task.new", title: "New Task") {},
    ]
}
