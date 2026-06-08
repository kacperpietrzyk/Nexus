import NexusCore
import NexusUI
import SwiftUI
import TasksFeature

struct TasksTab: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case today = "Today"
        case upcoming = "Upcoming"
        case inbox = "Inbox"
        case done = "Done"

        var id: String { rawValue }

        func toTaskFilter() -> TaskFilter {
            switch self {
            case .all: return .all
            case .today: return .today
            case .upcoming: return .upcoming
            case .inbox: return .inbox
            case .done: return .completed
            }
        }
    }

    let onOpenTask: (TaskItem) -> Void
    let onOpenCapture: () -> Void
    let onOpenCommandPalette: () -> Void
    var showsToolbarActions = true

    @State private var filter: Filter = .all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar

                TaskListView(filter: filter.toTaskFilter(), onSelect: onOpenTask)
                    .padding(.top, 4)
            }
            .navigationTitle("Tasks")
            .toolbarBackground(NexusColor.Background.base, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .toolbar {
                if showsToolbarActions {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onOpenCommandPalette) {
                            Image(systemName: "command")
                        }
                        .accessibilityLabel("Open command palette")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onOpenCapture) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Capture task")
                    }
                }
            }
        }
    }

    /// Equal-width, theme-native filter selector. Replaces `.pickerStyle(.segmented)`
    /// — the UIKit segmented control's light track is the one bright element on the
    /// dark Tasks surface and resists full appearance theming.
    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(Filter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Text(item.rawValue)
                        .font(NexusType.bodySmall.weight(item == filter ? .semibold : .medium))
                        .foregroundStyle(
                            item == filter ? NexusColor.Text.primary : NexusColor.Text.tertiary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            item == filter ? NexusColor.Background.controlHover : Color.clear,
                            in: RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == filter ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(
            NexusColor.Background.panel,
            in: RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .animation(NexusMotion.standard, value: filter)
    }
}
