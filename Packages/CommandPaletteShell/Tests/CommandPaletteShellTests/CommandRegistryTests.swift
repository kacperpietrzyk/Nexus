import SwiftUI
import Testing
@testable import CommandPaletteShell

@Suite("CommandRegistry")
struct CommandRegistryTests {

    @Test("registered commands are returned in title order")
    func registeredCommandsAreStable() async {
        let registry = CommandRegistry()
        await registry.register(RecordingCommand(id: "b", title: "Go to Inbox", keywords: ["tray"]))
        await registry.register(RecordingCommand(id: "a", title: "Add Task", keywords: ["capture"]))

        let commands = await registry.allCommands()
        #expect(commands.map(\.id) == ["a", "b"])
    }

    @Test("search matches title and keywords")
    func searchMatchesTitleAndKeywords() async {
        let registry = CommandRegistry()
        await registry.register(RecordingCommand(id: "add", title: "Add Task", keywords: ["capture"]))
        await registry.register(RecordingCommand(id: "today", title: "Go to Today", keywords: ["sun"]))

        let capture = await registry.search("cap")
        let sun = await registry.search("sun")

        #expect(capture.map(\.id) == ["add"])
        #expect(sun.map(\.id) == ["today"])
    }

    @Test("execute routes by command id")
    func executeRoutesByID() async throws {
        let registry = CommandRegistry()
        let command = RecordingCommand(id: "add", title: "Add Task", keywords: [])
        await registry.register(command)

        try await registry.execute(id: "add")

        let count = command.executionCount
        #expect(count == 1)
    }

    @Test("execute throws missingCommand for unknown id")
    func executeThrowsForUnknownID() async {
        let registry = CommandRegistry()

        await #expect(throws: CommandRegistryError.missingCommand("ghost")) {
            try await registry.execute(id: "ghost")
        }
    }

    @Test("execute throws disabledCommand when command is unavailable")
    func executeThrowsForUnavailableCommand() async {
        let registry = CommandRegistry()
        let command = RecordingCommand(
            id: "mark",
            title: "Mark Selected Done",
            keywords: [],
            availability: .disabled(reason: "Select a task first")
        )
        await registry.register(command)

        await #expect(
            throws: CommandRegistryError.disabledCommand(
                "mark",
                reason: "Select a task first"
            )
        ) {
            try await registry.execute(id: "mark")
        }

        let count = command.executionCount
        #expect(count == 0)
    }
}

@Suite("CommandPalette presentation")
struct CommandPalettePresentationTests {

    @Test("compact iOS hides visual keyboard chrome")
    func compactIOSHidesKeyboardChrome() {
        let presentation = CommandPalettePresentation.resolved(
            horizontalSizeClass: .compact,
            platform: .iOS
        )

        #expect(!presentation.showsEscapeKey)
        #expect(!presentation.showsCommandShortcuts)
        #expect(!presentation.showsKeyboardFooter)
    }

    @Test("regular iOS keeps keyboard chrome for wider hardware-keyboard layouts")
    func regularIOSKeepsKeyboardChrome() {
        let presentation = CommandPalettePresentation.resolved(
            horizontalSizeClass: .regular,
            platform: .iOS
        )

        #expect(presentation.showsEscapeKey)
        #expect(presentation.showsCommandShortcuts)
        #expect(presentation.showsKeyboardFooter)
    }

    @Test("macOS keeps keyboard chrome")
    func macOSKeepsKeyboardChrome() {
        let presentation = CommandPalettePresentation.resolved(
            horizontalSizeClass: nil,
            platform: .macOS
        )

        #expect(presentation.showsEscapeKey)
        #expect(presentation.showsCommandShortcuts)
        #expect(presentation.showsKeyboardFooter)
    }
}

private final class RecordingCommand: Command, @unchecked Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let iconName: String
    let keywords: [String]
    let shortcut: [String]
    private let commandAvailability: CommandAvailability
    private(set) var executionCount = 0

    init(
        id: String,
        title: String,
        keywords: [String],
        availability: CommandAvailability = .enabled
    ) {
        self.id = id
        self.title = title
        self.subtitle = nil
        self.iconName = "command"
        self.keywords = keywords
        self.shortcut = []
        self.commandAvailability = availability
    }

    var availability: CommandAvailability {
        get async { commandAvailability }
    }

    func execute() async throws {
        executionCount += 1
    }
}
