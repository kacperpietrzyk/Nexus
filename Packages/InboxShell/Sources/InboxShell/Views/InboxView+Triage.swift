import NexusUI
import SwiftUI

// Platform layouts, bulk actions, iOS compact row, and snooze picker.
// Extracted to keep InboxView.swift under swiftlint's file-length limit.

// MARK: - macOS layout

#if os(macOS)
extension InboxView {
    var macLayout: some View {
        VStack(spacing: 0) {
            macHeaderBand
            HStack(alignment: .top, spacing: 0) {
                InboxListPanel(
                    items: filteredItems,
                    error: error,
                    selectedItem: $selectedItem,
                    selection: selection,
                    onOpen: { item in open(item) },
                    onDismiss: { item in Task { await dismiss(item) } },
                    onSnooze: { item, hours in
                        let date = Date().addingTimeInterval(TimeInterval(hours * 60 * 60))
                        Task { await snooze(item, until: date) }
                    },
                    onCustomSnooze: { item in snoozeTarget = item }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Spacer(minLength: 36)

                InboxReaderPane(
                    item: selectedItem,
                    emptyState: filteredItems.isEmpty ? .emptyInbox : .noSelection,
                    onOpen: { item in open(item) },
                    onDismiss: { item in Task { await dismiss(item) } },
                    onSnooze: { item, hours in
                        let date = Date().addingTimeInterval(TimeInterval(hours * 60 * 60))
                        Task { await snooze(item, until: date) }
                    }
                )
                .frame(width: InboxLayout.readerWidth)
                .frame(maxHeight: .infinity)
                .padding(.top, 22)
                .padding(.bottom, 18)
                .padding(.trailing, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            BulkActionBar(model: selection, allIDs: filteredItems.map(\.id), actions: macBulkActions)
        }
        .task { await reload(selectFirstItem: true) }
        .reloadOnStoreChange {
            Task {
                await registry.invalidate()
                await reload(selectFirstItem: false)
            }
        }
        .sheet(item: $snoozeTarget) { item in
            SnoozePickerSheet(
                item: item,
                onConfirm: { date in
                    snoozeTarget = nil
                    Task { await snooze(item, until: date) }
                },
                onDismiss: { snoozeTarget = nil }
            )
        }
    }

    var macHeaderBand: some View {
        HStack(spacing: DS.Space.s) {
            Spacer()
            if selection.isSelecting {
                Button("Cancel") {
                    withAnimation(DS.Motion.panelReveal) { selection.exitSelection() }
                }
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .buttonStyle(.plain)
            } else {
                Button("Select") {
                    withAnimation(DS.Motion.panelReveal) { selection.enterSelection() }
                }
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    var macBulkActions: [BulkAction] {
        [
            BulkAction(label: "Dismiss", systemImage: "xmark.circle") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) && $0.stream != .bridge }
                selection.exitSelection()
                Task { for item in selected { await dismiss(item) } }
            },
            BulkAction(label: "Snooze 1h", systemImage: "moon.zzz") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) && $0.stream != .bridge }
                let date = Date().addingTimeInterval(3_600)
                selection.exitSelection()
                Task { for item in selected { await snooze(item, until: date) } }
            },
        ]
    }
}
#endif

// MARK: - iOS layout

extension InboxView {
    var iosLayout: some View {
        VStack(spacing: 8) {
            iosHeaderBand
                .padding(.horizontal, 16)
                .padding(.top, 8)
            inboxFilterBar
                .padding(.horizontal, 16)
            listContent
        }
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            BulkActionBar(model: selection, allIDs: filteredItems.map(\.id), actions: iosBulkActions)
        }
        .task { await reload(selectFirstItem: false) }
        .refreshable {
            await registry.invalidate()
            await reload(selectFirstItem: false)
        }
        .reloadOnStoreChange {
            Task {
                await registry.invalidate()
                await reload(selectFirstItem: false)
            }
        }
        .sheet(item: $snoozeTarget) { item in
            SnoozePickerSheet(
                item: item,
                onConfirm: { date in
                    snoozeTarget = nil
                    Task { await snooze(item, until: date) }
                },
                onDismiss: { snoozeTarget = nil }
            )
        }
    }

    var iosHeaderBand: some View {
        HStack {
            if selection.isSelecting {
                Button("Cancel") {
                    withAnimation(DS.Motion.panelReveal) { selection.exitSelection() }
                }
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .buttonStyle(.plain)
            }
            Spacer()
            if !selection.isSelecting {
                Button("Select") {
                    withAnimation(DS.Motion.panelReveal) { selection.enterSelection() }
                }
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.accentPrimary)
                .buttonStyle(.plain)
                .padding(.leading, DS.Space.s)
            }
        }
    }

    var iosBulkActions: [BulkAction] {
        [
            BulkAction(label: "Dismiss", systemImage: "xmark.circle") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) && $0.stream != .bridge }
                selection.exitSelection()
                Task { for item in selected { await dismiss(item) } }
            },
            BulkAction(label: "Snooze 1h", systemImage: "moon.zzz") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) && $0.stream != .bridge }
                let date = Date().addingTimeInterval(3_600)
                selection.exitSelection()
                Task { for item in selected { await snooze(item, until: date) } }
            },
        ]
    }

    var listContent: some View {
        List {
            if error != nil {
                ContentUnavailableView("Couldn't load the Inbox", systemImage: "exclamationmark.triangle")
                    .listRowBackground(Color.clear)
            } else if filteredItems.isEmpty {
                ContentUnavailableView(
                    "Inbox is empty",
                    systemImage: "tray",
                    description: Text("New agent insights and meeting summaries appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems) { item in
                    Button {
                        if selection.isSelecting {
                            withAnimation(DS.Motion.selection) { selection.toggle(id: item.id) }
                        } else {
                            open(item)
                        }
                    } label: {
                        InboxCompactRow(item: item, isUnread: item.seenAt == nil && item.stream != .bridge)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .selectable(
                        isSelecting: selection.isSelecting,
                        isSelected: selection.isSelected(id: item.id),
                        onToggle: { selection.toggle(id: item.id) }
                    )
                    .onLongPressGesture {
                        selection.enterSelection()
                        withAnimation(DS.Motion.selection) { selection.toggle(id: item.id) }
                    }
                    .contextMenu { iosContextMenu(for: item) }
                    .swipeActions(edge: .trailing) {
                        if item.stream != .bridge {
                            Button {
                                Task { await snooze(item, until: Date().addingTimeInterval(3_600)) }
                            } label: {
                                Label("1h", systemImage: "clock")
                            }
                            .tint(DS.ColorToken.textSecondary)
                            Button(role: .destructive) {
                                Task { await dismiss(item) }
                            } label: {
                                Label("Dismiss", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    func iosContextMenu(for item: FeedItem) -> some View {
        Button {
            open(item)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        if item.stream != .bridge {
            Divider()
            Menu("Snooze") {
                Button {
                    Task { await snooze(item, until: Date().addingTimeInterval(3_600)) }
                } label: {
                    Label("1 Hour", systemImage: "clock")
                }
                Button {
                    snoozeTarget = item
                } label: {
                    Label("Custom\u{2026}", systemImage: "calendar")
                }
            }
            Button(role: .destructive) {
                Task { await dismiss(item) }
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
    }
}

// MARK: - iOS compact row

struct InboxCompactRow: View {
    let item: FeedItem
    let isUnread: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(isUnread ? DS.ColorToken.accentPrimary : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(isUnread ? DS.FontToken.bodyStrong : DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Snooze picker sheet

/// Minimal date-picker sheet for "Custom snooze".
struct SnoozePickerSheet: View {
    let item: FeedItem
    let onConfirm: (Date) -> Void
    let onDismiss: () -> Void

    @State private var date = Date().addingTimeInterval(3_600)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            Text("Snooze Until")
                .font(DS.FontToken.title)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Text(item.title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(2)
            DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack(spacing: DS.Space.s) {
                Button("Cancel", action: onDismiss)
                    .font(DS.FontToken.button)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .buttonStyle(.plain)
                Spacer()
                LiquidPrimaryButton("Snooze", systemImage: "moon.zzz") { onConfirm(date) }
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: 360)
        .presentationDetents([.medium])
        .presentationBackground(.thinMaterial)
    }
}
