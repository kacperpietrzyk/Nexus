import CommandPaletteShell
import Foundation

/// Opens (or creates) today's daily note (O4). The closure is supplied by the
/// app's composition root: it routes navigation to the Notes surface and fires
/// `DailyNoteOpenRequest` — the app owns destination state, this module doesn't.
/// Mirrors the closure-injection shape of `TaskCommands` (TasksFeature).
public final class OpenDailyNoteCommand: Command, @unchecked Sendable {
    public let id = "notes.open-daily-note"
    public let title = "Open Today's Note"
    public let subtitle: String? = "Open or create the daily note for today"
    public let iconName = "calendar.badge.plus"
    public let keywords = ["daily", "today", "journal", "note", "brief"]
    public let shortcut = ["⌘", "⇧", "D"]
    private let action: @MainActor @Sendable () -> Void

    public init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    public func execute() async throws {
        await MainActor.run { action() }
    }
}

/// Opens the O1 graph view. The closure is supplied by the app's composition
/// root: it routes to the Notes surface and fires `GraphOpenRequest`. Hosts that
/// do not wire the graph simply do not register this command.
public final class OpenGraphCommand: Command, @unchecked Sendable {
    public let id = "notes.open-graph"
    public let title = "Open Graph View"
    public let subtitle: String? = "Visualize the link graph"
    public let iconName = "point.3.connected.trianglepath.dotted"
    public let keywords = ["graph", "links", "network", "map", "connections"]
    public let shortcut: [String] = []
    private let action: @MainActor @Sendable () -> Void

    public init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    public func execute() async throws {
        await MainActor.run { action() }
    }
}
