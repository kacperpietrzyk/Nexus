import NexusUI
import SwiftData
import SwiftUI

#if os(macOS)
public struct MeetingsListView: View {
    @StateObject private var viewModel: MeetingsListViewModel
    @ObservedObject var router: MeetingNavigationRouter
    private let onItemsChanged: (Bool) -> Void

    public init(
        repository: MeetingRepository,
        router: MeetingNavigationRouter,
        onItemsChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: MeetingsListViewModel(repository: repository))
        self.router = router
        self.onItemsChanged = onItemsChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchField
            filterMenu

            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(height: 1)

            if viewModel.items.isEmpty {
                MeetingsListEmptyState(
                    isSearching: !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.items) { meeting in
                            MeetingsListRow(
                                meeting: meeting,
                                isSelected: router.selectedMeetingID == meeting.id
                            ) {
                                router.navigate(to: meeting.id)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(NexusColor.Background.panel)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.36), radius: 18, x: -6, y: 8)
        .onAppear {
            viewModel.reload()
            publishItemsState()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            viewModel.reload()
            publishItemsState()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NexusColor.Text.muted)
            TextField("Search meetings...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.secondary)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.reload()
                    publishItemsState()
                }
        }
        .padding(.horizontal, 11)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(NexusColor.Background.control.opacity(0.82))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(MeetingsFilter.allCases) { filter in
                Button(filter.label) {
                    viewModel.filter = filter
                    viewModel.reload()
                    publishItemsState()
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12, weight: .medium))
                Text(viewModel.filter.label)
                    .font(NexusType.meta)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.muted)
            }
            .foregroundStyle(NexusColor.Text.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NexusColor.Background.control.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private func publishItemsState() {
        onItemsChanged(!viewModel.items.isEmpty)
    }
}

private struct MeetingsListRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NexusColor.Text.muted)
                    .frame(width: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(Font.custom("Inter-Medium", size: 13))
                        .foregroundStyle(isSelected ? NexusColor.Text.primary : NexusColor.Text.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(NexusType.metaMono)
                            .monospacedDigit()
                            .foregroundStyle(NexusColor.Text.disabled)

                        if !meeting.actionItemIDs.isEmpty {
                            Label("\(meeting.actionItemIDs.count)", systemImage: "checklist")
                                .font(NexusType.meta)
                                .foregroundStyle(NexusColor.Text.muted)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? NexusColor.Background.controlHover : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct MeetingsListEmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isSearching ? "magnifyingglass" : "person.wave.2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(NexusColor.Text.muted)
            Text(isSearching ? "No results" : "No meetings")
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.secondary)
            Text(
                isSearching
                    ? "Try a different search or filter."
                    : "Recordings and imports will appear here."
            )
            .font(NexusType.meta)
            .foregroundStyle(NexusColor.Text.muted)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 150)
    }
}
#endif
