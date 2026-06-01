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
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
}
