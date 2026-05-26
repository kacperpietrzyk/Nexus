import NexusCore
import SwiftUI

/// Living style guide for the v4 NexusUI token and primitive set.
public struct DesignSystemShowcase: View {
    public init() {}

    public var body: some View {
        ShowcaseState()
    }
}

private struct ShowcaseState: View {
    @State private var navSelection = "today"
    @State private var tabSelection = "open"
    @State private var checked = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                tokensSection
                #if !os(watchOS)
                navSection
                topBarSection
                tabBarSection
                #endif
                statusPrioritySection
                dayProgressSection
                timeRowSection
                avatarCheckboxSection
                buttonSection
                badgeSection
                chipSection
                sharedViewsSection
            }
            .padding(32)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NexusColor.Background.base)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nexus Design System")
                .nexusType(.display)
                .foregroundStyle(NexusColor.Text.primary)
            Text("v\(NexusUI.version) / coss-azure")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.primary)
        }
    }

    private var tokensSection: some View {
        section("Tokens") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    swatch("base", NexusColor.Background.base)
                    swatch("panel", NexusColor.Background.panel)
                    swatch("raised", NexusColor.Background.raised)
                    swatch("control", NexusColor.Background.control)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Display 48").nexusType(.display).foregroundStyle(NexusColor.Text.primary)
                    Text("H1 32").nexusType(.h1).foregroundStyle(NexusColor.Text.primary)
                    Text("H2 22").nexusType(.h2).foregroundStyle(NexusColor.Text.primary)
                    Text("Body text for dense operational screens.")
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.secondary)
                    Text("eyebrow label").nexusType(.eyebrow).foregroundStyle(NexusColor.Text.muted)
                }
            }
        }
    }

    #if !os(watchOS)
    private var navSection: some View {
        section("NavRail") {
            NexusNavRail(
                items: [
                    NexusNavRailItem(id: "today", systemImage: "sun.max.fill", label: "Today", count: 7),
                    NexusNavRailItem(id: "inbox", systemImage: "tray", label: "Inbox", count: 3),
                    NexusNavRailItem(id: "settings", systemImage: "gearshape", label: "Settings"),
                ],
                active: $navSelection,
                logoTitle: "N",
                avatar: { NexusAvatar(name: "Kacper Pietrzyk") }
            )
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
        }
    }

    private var topBarSection: some View {
        section("TopBar") {
            NexusTopBar(crumbs: ["Nexus", "Today"]) {
                NexusBadge("Synced", tone: .pos)
            }
            .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
        }
    }

    private var tabBarSection: some View {
        section("TabBar") {
            NexusTabBar(
                items: [
                    NexusTabBarItem(id: "open", label: "Open", systemImage: "circle", count: 8),
                    NexusTabBarItem(id: "done", label: "Done", systemImage: "checkmark.circle", count: 4),
                    NexusTabBarItem(id: "blocked", label: "Blocked", systemImage: "minus.circle", count: 2),
                ],
                active: $tabSelection
            )
        }
    }
    #endif

    private var statusPrioritySection: some View {
        section("Status + Priority") {
            HStack(spacing: 24) {
                ForEach(statusSamples, id: \.label) { sample in
                    VStack(spacing: 8) {
                        NexusStatusGlyph(sample.status)
                        Text(sample.label).nexusType(.caption).foregroundStyle(NexusColor.Text.tertiary)
                    }
                }

                Divider().frame(height: 32)

                ForEach(NexusPriorityLevel.allCases, id: \.self) { level in
                    NexusPriorityBars(level)
                }
            }
        }
    }

    private var dayProgressSection: some View {
        section("DayProgress") {
            NexusDayProgress(
                progress: 0.42,
                tickFractions: [0.12, 0.34, 0.72],
                doneCount: 5,
                totalCount: 12,
                focusedMinutes: 138
            )
        }
    }

    private var timeRowSection: some View {
        section("TimeRow") {
            VStack(alignment: .leading, spacing: 0) {
                NexusTimeRow("09:30") {
                    timelineCard("Planning window")
                }
                NexusTimeRow("10:00", isCurrent: true) {
                    timelineCard("Focus block")
                }
            }
        }
    }

    private var avatarCheckboxSection: some View {
        section("Avatar + Checkbox") {
            HStack(spacing: 18) {
                NexusAvatar(name: "Kacper Pietrzyk", size: 30)
                NexusAvatar(name: "Nexus", size: 30, hue: 205)
                NexusCheckbox(isChecked: $checked, accessibilityLabel: "Done")
            }
        }
    }

    private var buttonSection: some View {
        section("Button") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(NexusButtonVariant.allCases, id: \.self) { variant in
                    HStack(spacing: 10) {
                        ForEach(NexusButtonSize.allCases, id: \.self) { size in
                            NexusButton(
                                variant: variant, size: size, action: {},
                                label: {
                                    if size == .icon || size == .iconSm {
                                        Image(systemName: "plus")
                                    } else {
                                        Text(buttonLabel(variant, size))
                                    }
                                })
                        }
                    }
                }
            }
        }
    }

    private var badgeSection: some View {
        section("Badge") {
            HStack(spacing: 10) {
                ForEach(NexusBadgeTone.allCases, id: \.self) { tone in
                    NexusBadge("\(tone)", tone: tone)
                }
            }
        }
    }

    private var chipSection: some View {
        section("Chip") {
            HStack(spacing: 10) {
                ForEach(NexusChipTone.allCases, id: \.self) { tone in
                    NexusChip("\(tone)", tone: tone)
                }
            }
        }
    }

    private var sharedViewsSection: some View {
        section("Shared Views") {
            VStack(alignment: .leading, spacing: 14) {
                ItemRow(item: TaskItem(title: "Plan next visual pass"))
                BacklinksView(items: [
                    TaskItem(title: "Phase 1 Visual Refactor v4"),
                    TaskItem(title: "Coss Azure primitive sweep"),
                ])
                NexusEditor(markdown: "**Read-only Markdown** for the showcase.")
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
            }
        }
    }

    private var statusSamples: [(label: String, status: NexusStatus)] {
        [
            ("todo", .todo),
            ("progress", .inProgress(0.45)),
            ("review", .inReview),
            ("done", .done),
            ("cancelled", .cancelled),
        ]
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        NexusCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
                content()
            }
        }
    }

    private func swatch(_ label: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                .fill(color)
                .frame(width: 64, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                        .strokeBorder(NexusColor.Line.hairline)
                )
            Text(label)
                .nexusType(.caption)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
    }

    private func timelineCard(_ title: String) -> some View {
        NexusCard(padding: 14) {
            Text(title)
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.primary)
        }
    }

    private func buttonLabel(_ variant: NexusButtonVariant, _ size: NexusButtonSize) -> String {
        "\(variant) \(size)"
    }
}

#Preview {
    DesignSystemShowcase()
        .frame(width: 1000, height: 1400)
}
