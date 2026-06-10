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
                .frame(width: 270)

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
