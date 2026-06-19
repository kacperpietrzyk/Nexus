import CommandPaletteShell
import Foundation

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
