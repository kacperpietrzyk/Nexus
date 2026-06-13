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

/// Today-specific command-center control. Other destinations keep breadcrumbs;
/// Today matches the reference topbar composition without inventing day-state
/// plumbing in the app shell.
struct LiquidTodayToolbarControl: View {
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.m) {
            LiquidIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Previous day",
                action: {}
            )
            .disabled(true)
            .opacity(0.72)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                LiquidToolbarSegmentIcon(systemImage: "chevron.left")
                LiquidToolbarSegmentSeparator()
                Text("Today")
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .frame(width: 88, height: 32)
                LiquidToolbarSegmentSeparator()
                LiquidToolbarSegmentIcon(systemImage: "chevron.right")
            }
            .padding(2)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.030))
                    .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                    .overlay {
                        LinearGradient(
                            colors: [Color.white.opacity(0.070), .clear, Color.black.opacity(0.040)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(Capsule(style: .continuous))
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.095), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)

            Button(action: onOpenCalendar) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open calendar")
            .accessibilityLabel("Open calendar")

            Spacer(minLength: 0)
        }
    }
}

private struct LiquidToolbarSegmentIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS.ColorToken.textSecondary)
            .frame(width: 36, height: 32)
    }
}

private struct LiquidToolbarSegmentSeparator: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.075))
            .frame(width: 1, height: 16)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }
}
