// A generic command-palette entry that runs a shell navigation closure.
//
// The feature packages ship destination commands for the surfaces they own
// (Tasks ships `GoToTodayCommand` / `GoToInboxCommand`); the remaining shell
// destinations — and the bounded project/person quick-jump entries — have no
// natural package home, so the macOS shell registers them itself via this one
// generic type. It mirrors the package commands' shape: stored metadata plus a
// `@MainActor @Sendable` action closure that `execute()` hops onto the main
// actor (navigation mutates `@State NexusNavigator`).
//
// A `struct` whose stored properties are all `Sendable` conforms to `Sendable`
// implicitly, so — unlike the `final class … @unchecked Sendable` package
// commands — this needs no `@unchecked`.

import CommandPaletteShell
import TasksFeature

struct ShellNavigateCommand: Command {
    let id: String
    let title: String
    let subtitle: String?
    let iconName: String
    let keywords: [String]
    let shortcut: [String]
    private let action: @MainActor @Sendable () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        iconName: String,
        keywords: [String],
        shortcut: [String] = [],
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.keywords = keywords
        self.shortcut = shortcut
        self.action = action
    }

    func execute() async throws {
        await MainActor.run { action() }
    }
}

/// Static description of one shell-destination palette command, used to drive
/// `registerDestinationCommands()` from a table without a many-membered tuple.
struct DestinationCommandSpec {
    let destination: TodayNavSelection
    let name: String
    let icon: String
    let keywords: [String]

    init(_ destination: TodayNavSelection, _ name: String, _ icon: String, _ keywords: [String]) {
        self.destination = destination
        self.name = name
        self.icon = icon
        self.keywords = keywords
    }
}
