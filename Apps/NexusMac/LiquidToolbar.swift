import NexusUI
import SwiftUI

/// The 58 pt Liquid toolbar that tops the glass content shell
/// (`docs/03_COMPONENTS.md` §Toolbar). Leading is a per-destination slot
/// (breadcrumb title, Inbox filter tabs, the Agent control strip, …);
/// trailing is the fixed search → bell → New cluster wired to the SAME seams
/// the old `NexusTopBar`/`NexusCommandBar` band used:
/// - search field → command palette (the global ⌘K `CommandGroup` still
///   posts `.nexusOpenCommandPalette`, handled by `ContentView`)
/// - bell → Inbox destination
/// - New → the existing capture seam (`.nexusOpenCapture`, same as ⌘N/⌘⌃N)
struct LiquidToolbar<Leading: View>: View {
    @ViewBuilder let leading: () -> Leading
    let onOpenCommandPalette: () -> Void
    let onOpenInbox: () -> Void
    let onOpenCapture: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.m) {
            leading()
                .frame(maxWidth: .infinity, alignment: .leading)

            LiquidSearchField("Search anything…", action: onOpenCommandPalette)
                .frame(width: 300)

            LiquidIconButton(
                systemImage: "bell",
                accessibilityLabel: "Open inbox",
                action: onOpenInbox
            )
            .help("Open inbox")

            LiquidPrimaryButton("New", systemImage: "plus", action: onOpenCapture)
                .help("New task (⌘N)")
                .accessibilityLabel("New task")
        }
        .padding(.horizontal, DS.Space.l)
        .frame(height: DS.Size.toolbarHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(height: 1)
                .padding(.horizontal, DS.Space.l)
        }
    }
}

/// Breadcrumb/title leading content for plain destinations — the Liquid
/// replacement for `NexusTopBar`'s `crumbs` (e.g. "Personal / Today": parent
/// crumbs muted, current page emphasized).
struct LiquidToolbarBreadcrumb: View {
    let crumbs: [String]

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(crumbs.dropLast().enumerated()), id: \.offset) { _, crumb in
                Text(crumb)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                Text("/")
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
            if let current = crumbs.last {
                Text(current)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// Today-specific leading title: the page title "Today" stacked over the
/// formatted current date. Lives in the toolbar band (in place of the old
/// in-content header), so the Today content cards start higher and align with
/// the right Daily Brief rail. Other destinations keep breadcrumbs.
struct LiquidTodayTitle: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Today")
                .font(DS.FontToken.title)
                .foregroundStyle(DS.ColorToken.textPrimary)
            // Real formatted date only — no fabricated weather/day-state chip.
            Text(Self.dateFormatter.string(from: .now))
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()
}
