import CommandPaletteShell
import Foundation
import Testing

@testable import NotesFeature

@MainActor
struct NoteCommandsTests {
    /// `@unchecked Sendable` mutable box; the action runs on MainActor.
    private final class Flag: @unchecked Sendable {
        var value = false
    }

    @Test func bootstrapRegistersOpenDailyNoteCommand() async throws {
        let registry = CommandRegistry()

        await NotesComposition.bootstrap(commandRegistry: registry, openDailyNote: {})

        let ids = await registry.allCommands().map(\.id)
        #expect(ids == ["notes.open-daily-note"])
    }

    @Test func openDailyNoteCommandCarriesShortcutAndKeywords() async throws {
        let command = OpenDailyNoteCommand(action: {})

        #expect(command.shortcut == ["⌘", "⇧", "D"])
        #expect(command.keywords.contains("daily"))
        #expect(command.keywords.contains("today"))
    }

    @Test func executeRunsTheInjectedAction() async throws {
        let registry = CommandRegistry()
        let fired = Flag()
        await NotesComposition.bootstrap(
            commandRegistry: registry,
            openDailyNote: { fired.value = true }
        )

        try await registry.execute(id: "notes.open-daily-note")

        #expect(fired.value)
    }
}
