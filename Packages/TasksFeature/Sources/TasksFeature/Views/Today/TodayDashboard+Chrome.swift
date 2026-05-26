import SwiftUI

/// Controls how much of its own chrome `TodayDashboard` draws.
///
/// - `standalone`: the dashboard owns its full frame — wallpaper, the wide
///   text sidebar (Mac) and the in-column top-bar pill. This is the iOS and
///   legacy Mac behaviour.
/// - `embedded`: the dashboard is mounted inside an outer Nexus shell that
///   already paints the wallpaper, the icon-rail and the glass top-bar pill,
///   so the dashboard renders only its route content (the shell is the
///   organism; the dashboard is the content slot). UI-only — no behaviour or
///   data change; selection/capture/command callbacks are unchanged.
public enum TodayDashboardChrome: Sendable {
    case standalone
    case embedded
}

/// Applies the platform/chrome-correct outer frame.
///
/// - Standalone macOS keeps the legacy minimum window-content size.
/// - Embedded (mounted in the Nexus shell) takes no fixed minimum — the
///   shell and the inner main-column `minWidth` own sizing — and just
///   fills the shell's content slot.
/// - iOS is unchanged.
struct DashboardFrame: ViewModifier {
    let chrome: TodayDashboardChrome

    func body(content: Content) -> some View {
        #if os(iOS)
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        switch chrome {
        case .embedded:
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        case .standalone:
            content.frame(minWidth: 980, minHeight: 640)
        }
        #endif
    }
}
