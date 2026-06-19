import NexusCore
import NexusUI
import SwiftData
import SwiftUI
import TasksFeature

/// Vertical clearance reserved for the REAL macOS traffic lights. The main
/// window is `.hiddenTitleBar`, so AppKit draws the close/minimize/zoom
/// buttons directly over the top-left of the content — i.e. over this
/// sidebar's top band (outer window padding 12 + sidebar padding 12 puts the
/// first row at y≈24, the lights extend to y≈30). Reserved as empty space;
/// never drawn (the design-system example's painted circles are placeholder).
private let trafficLightClearance: CGFloat = 58
private let sidebarCornerRadius: CGFloat = 16

/// The Liquid 224 pt glass sidebar — REAL app data only.
///
/// Primary nav mirrors the destinations of the old 54 pt `NexusNavRail`
/// (same `TodayNavSelection` cases; order per the Liquid reference design),
/// with Stats + Settings pinned to a bottom section. "PROJECTS" lists active
/// projects (status `.active`, not archived, top 5 by `updatedAt`);
/// "VIEWS" lists the user's `SavedFilter` smart lists. Both sections hide
/// entirely when empty — no fake rows. The footer is the real macOS account
/// display name and routes to Settings.
///
/// Navigation goes through the host's `onNavigate` closure, which wraps the
/// existing `ContentView.navigate(to:)` chokepoint (animated envelope + the
/// "inspector ⊥ Agent" `.onChange` invariant stay intact).
struct LiquidSidebar: View {
    let selection: TodayNavSelection
    let inboxUnreadCount: Int
    /// The UUID of the active saved filter, if any. Drives the selected state
    /// on "Views" rows — set by the shell when `taskFilter == .savedFilter(id)`.
    var activeSavedFilterID: UUID?
    let onNavigate: (TodayNavSelection) -> Void
    /// Stages a deep link for a sidebar shortcut row (e.g. a project).
    /// The host calls `navigator.open(_:deepLink:)` wrapped in animation.
    let onDeepLink: (TodayNavSelection, DeepLinkTarget) -> Void

    @Query private var projects: [Project]
    @Query(sort: \SavedFilter.orderIndex) private var savedFilters: [SavedFilter]

    /// Same destinations the old rail exposed (minus the bottom-pinned
    /// Stats/Settings); SF symbols carried over 1:1 from `railItems`.
    private var primaryItems: [SidebarNavEntry] {
        [
            SidebarNavEntry(id: .today, label: "Today", systemImage: "circle.dotted"),
            SidebarNavEntry(id: .inbox, label: "Inbox", systemImage: "tray"),
            SidebarNavEntry(id: .calendar, label: "Calendar", systemImage: "calendar"),
            SidebarNavEntry(id: .meetings, label: "Meetings", systemImage: "person.wave.2"),
            SidebarNavEntry(id: .tasks, label: "Tasks", systemImage: "checkmark.square"),
            SidebarNavEntry(id: .notes, label: "Notes", systemImage: "note.text"),
            SidebarNavEntry(id: .projects, label: "Projects", systemImage: "square.stack.3d.up"),
            SidebarNavEntry(id: .people, label: "People", systemImage: "person.crop.circle"),
            SidebarNavEntry(id: .agent, label: "Agent", systemImage: "sparkles"),
        ]
    }

    private var activeProjects: [Project] {
        projects
            .filter { $0.deletedAt == nil && $0.archivedAt == nil && $0.status == .active }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { $0 }
    }

    private var visibleSavedFilters: [SavedFilter] {
        savedFilters.filter { $0.deletedAt == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            sidebarTopControl

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                ForEach(primaryItems) { item in
                    LiquidSidebarNavRow(
                        item.label,
                        systemImage: item.systemImage,
                        badge: item.id == .inbox && inboxUnreadCount > 0 ? inboxUnreadCount : nil,
                        isSelected: selection == item.id
                    ) {
                        onNavigate(item.id)
                    }
                }
            }

            if !activeProjects.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    LiquidSidebarSectionHeader("Projects")
                        .padding(.horizontal, DS.Space.s)
                    ForEach(activeProjects) { project in
                        LiquidSidebarNavRow(
                            project.name,
                            systemImage: nexusProjectGlyph(token: project.color, id: project.id)
                        ) {
                            onDeepLink(.projects, .project(project.id))
                        }
                    }
                }
            }

            if !visibleSavedFilters.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    LiquidSidebarSectionHeader("Views")
                        .padding(.horizontal, DS.Space.s)
                    ForEach(visibleSavedFilters) { filter in
                        LiquidSidebarNavRow(
                            filter.name,
                            systemImage: filter.icon,
                            isSelected: filter.id == activeSavedFilterID
                        ) {
                            onDeepLink(.tasks, .savedFilter(filter.id))
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                LiquidSidebarNavRow(
                    "Stats",
                    systemImage: "chart.bar",
                    isSelected: selection == .stats
                ) {
                    onNavigate(.stats)
                }
                LiquidSidebarNavRow(
                    "Settings",
                    systemImage: "gearshape",
                    isSelected: selection == .settings
                ) {
                    onNavigate(.settings)
                }
            }

            footer
        }
        .padding(DS.Space.m)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
        .liquidGlass(.sidebar, radius: sidebarCornerRadius)
    }

    private var sidebarTopControl: some View {
        HStack {
            Spacer(minLength: 0)

            LiquidIconButton(
                systemImage: "slider.horizontal.3",
                accessibilityLabel: "Open settings"
            ) {
                onNavigate(.settings)
            }
            .help("Open settings")
        }
        .frame(height: trafficLightClearance, alignment: .top)
    }

    /// Real macOS account display name + an initials avatar; opens Settings.
    private var footer: some View {
        Button {
            onNavigate(.settings)
        } label: {
            HStack(spacing: DS.Space.s) {
                Text(initials)
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .frame(width: 30, height: 30)
                    .background {
                        Circle()
                            .fill(DS.ColorToken.glassSelected)
                    }
                    .overlay {
                        Circle()
                            .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
                    }

                Text(displayName)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(DS.Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayName), open settings")
    }

    private var displayName: String {
        let full = NSFullUserName()
        return full.isEmpty ? NSUserName() : full
    }

    private var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "N" : String(letters).uppercased()
    }
}

/// One primary sidebar destination (id + label + SF symbol).
private struct SidebarNavEntry: Identifiable {
    let id: TodayNavSelection
    let label: String
    let systemImage: String
}
