import CommandPaletteShell
import Foundation

/// Command-palette entry for "Mark All Inbox Read". Posts the existing
/// `.nexusMarkInboxRead` notification — the SAME path the shell's "Mark Read"
/// header button uses and that `InboxView` already observes (it fetches EVERY
/// inbox id and marks them read, not just the loaded window). Self-contained:
/// no closure injection needed because the notification is the contract.
public final class MarkAllInboxReadCommand: Command, @unchecked Sendable {
    public let id = "inbox.mark-all-read"
    public let title = "Mark All Inbox Read"
    public let subtitle: String? = "Clear the inbox unread badge"
    public let iconName = "envelope.open"
    public let keywords = ["inbox", "read", "clear", "unread", "mark"]
    public let shortcut: [String] = []

    public init() {}

    public func execute() async throws {
        await MainActor.run {
            NotificationCenter.default.post(name: .nexusMarkInboxRead, object: nil)
        }
    }
}

/// Command-palette entry for "Select All Items" in the active list surface.
/// Posts `.nexusSelectAllActiveSurface`, which selectable surfaces observe to
/// enter selection mode + select their visible rows — the palette mirror of the
/// menu-bar ⌘A. macOS / iPad mount exactly one list destination at a time; the
/// compact-iPhone `TabView` keeps tabs mounted, but the palette is presented
/// over the visible tab, so the intended (foreground) surface still responds.
public final class SelectAllItemsCommand: Command, @unchecked Sendable {
    public let id = "shell.select-all-items"
    public let title = "Select All Items"
    public let subtitle: String? = "Enter multi-select on the current list"
    public let iconName = "checkmark.circle"
    public let keywords = ["select", "all", "multi", "bulk", "selection"]
    public let shortcut = ["⌘", "A"]

    public init() {}

    public func execute() async throws {
        await MainActor.run {
            NotificationCenter.default.post(name: .nexusSelectAllActiveSurface, object: nil)
        }
    }
}
