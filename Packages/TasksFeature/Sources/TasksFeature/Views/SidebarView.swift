import NexusUI
import SwiftUI

public struct SidebarView: View {
    @Binding private var selection: TodayNavSelection
    @Binding private var taskFilter: TaskFilter
    private let inboxUnreadCount: Int
    private let taskFilterTitle: String?
    private let onOpenCapture: (CapturePane.Mode) -> Void

    public init(
        selection: Binding<TodayNavSelection>,
        taskFilter: Binding<TaskFilter>,
        inboxUnreadCount: Int = 0,
        taskFilterTitle: String? = nil,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void = { _ in }
    ) {
        self._selection = selection
        self._taskFilter = taskFilter
        self.inboxUnreadCount = inboxUnreadCount
        self.taskFilterTitle = taskFilterTitle
        self.onOpenCapture = onOpenCapture
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    brand

                    VStack(alignment: .leading, spacing: 4) {
                        SidebarRow(
                            title: "Today",
                            systemImage: "circle.dotted",
                            count: nil,
                            isSelected: selection == .today,
                            action: { selection = .today }
                        )
                        SidebarRow(
                            title: "Inbox",
                            systemImage: "tray",
                            count: inboxUnreadCount,
                            isSelected: selection == .inbox,
                            action: { selection = .inbox }
                        )
                        SidebarRow(
                            title: "Meetings",
                            systemImage: "person.wave.2",
                            count: nil,
                            isSelected: selection == .meetings,
                            action: { selection = .meetings }
                        )
                        SidebarRow(
                            title: taskFilterTitle ?? taskFilter.displayTitle,
                            systemImage: "checkmark.square",
                            count: nil,
                            isSelected: selection == .tasks,
                            action: { selection = .tasks }
                        )
                        SidebarRow(
                            title: "Settings",
                            systemImage: "gearshape",
                            count: nil,
                            isSelected: selection == .settings,
                            action: { selection = .settings }
                        )
                    }

                    Divider()
                        .overlay(NexusColor.Line.hairline)

                    ProjectsSidebarSection(selection: $taskFilter) {
                        selection = .tasks
                    }

                    CyclesSidebarSection(
                        selection: $taskFilter,
                        onSelect: {
                            selection = .tasks
                        })

                    SmartListsSidebarSection(
                        selection: $taskFilter,
                        onSelect: {
                            selection = .tasks
                        })

                    SidebarRow(
                        title: "Statystyki",
                        systemImage: "chart.bar",
                        count: nil,
                        isSelected: selection == .stats,
                        action: { selection = .stats }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)

            NexusButton(
                variant: .primary, size: .md, action: { onOpenCapture(.task) },
                label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New Task")
                    }
                })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: 248)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(NexusColor.Background.base.opacity(0.82))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(width: 1)
        }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            Text("N")
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(NexusColor.Text.primary)
                .frame(width: 32, height: 32)
                .background(
                    NexusColor.Background.controlHover,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .nexusShadow(NexusShadow.s1)

            VStack(alignment: .leading, spacing: 1) {
                Text("Nexus")
                    .font(NexusType.body.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                Text("Personal")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                    .frame(width: 18)

                Text(title)
                    .nexusType(.bodySmall)
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(NexusType.caption)
                        .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(NexusColor.Background.control, in: Capsule())
                }
            }
            .frame(height: 32)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                        .fill(NexusColor.Background.controlHover)
                }
            }
        }
        .buttonStyle(.plain)
        .nexusRowHover()
        .accessibilityLabel(title)
    }
}
