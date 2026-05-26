import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct SmartListsSidebarSection: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SavedFilter.orderIndex) private var queriedFilters: [SavedFilter]

    @Binding private var selection: TaskFilter
    private let onSelect: () -> Void

    @State private var isPresentingSaveSheet = false
    @State private var error: String?

    public init(selection: Binding<TaskFilter>, onSelect: @escaping () -> Void = {}) {
        self._selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if filters.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filters) { filter in
                        SmartListSidebarRow(
                            title: filter.name,
                            systemImage: filter.icon,
                            isSelected: selection == .savedFilter(filter.id)
                        ) {
                            selection = .savedFilter(filter.id)
                            onSelect()
                        }
                        .contextMenu {
                            Button("Delete Smart List", role: .destructive) {
                                delete(filter)
                            }
                        }
                    }
                }
            }

            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(2)
            }
        }
        .sheet(isPresented: $isPresentingSaveSheet) {
            SaveCurrentFilterSheet(currentFilter: selection) { filter in
                selection = .savedFilter(filter.id)
                onSelect()
            }
        }
    }

    private var filters: [SavedFilter] {
        queriedFilters.filter { $0.deletedAt == nil }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Smart Lists")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            Spacer()

            NexusButton(
                variant: .ghost, size: .iconSm, action: { isPresentingSaveSheet = true },
                label: {
                    Image(systemName: "plus")
                }
            )
            .help("Save current filter")
            .accessibilityLabel("Save current filter")
        }
    }

    private var emptyState: some View {
        Button {
            isPresentingSaveSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text("Save current filter")
                Spacer()
            }
            .nexusType(.bodySmall)
            .foregroundStyle(NexusColor.Text.tertiary)
            .frame(height: 30)
        }
        .buttonStyle(.plain)
        .nexusRowHover()
    }

    @MainActor
    private func delete(_ filter: SavedFilter) {
        do {
            try SavedFilterRepository(context: modelContext).delete(filter)
            if selection == .savedFilter(filter.id) {
                selection = .upcoming
                onSelect()
            }
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct SmartListSidebarRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                    .frame(width: 16)

                Text(title)
                    .nexusType(.bodySmall)
                    .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)
            }
            .frame(height: 30)
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

    private var iconName: String {
        let trimmed = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "line.3.horizontal.decrease.circle" : trimmed
    }
}
