import NexusUI
import SwiftUI

// Platform layouts, bulk actions, iOS compact row, snooze picker, and context
// menus — extracted to keep InboxView.swift under swiftlint's 400-line limit.
// Mirrors the TodayDashboard+DigestData.swift / +Standalone.swift pattern.

// MARK: - macOS layout

#if os(macOS)
extension InboxView {
    var macLayout: some View {
        // Inbox-oracle 2-column geometry: LEFT list panel + RIGHT reader pane
        // fixed 380. §1a control mode: filter tabs live in the Mac shell top-bar.
        VStack(spacing: 0) {
            macHeaderBand
            HStack(alignment: .top, spacing: 0) {
                InboxListPanel(
                    items: filteredItems,
                    error: error,
                    totalsBySourceID: sourceTotals,
                    readItemIDs: $readItemIDs,
                    selectedItem: $selectedItem,
                    selection: selection,
                    onReachEnd: { Task { await loadMore() } },
                    onMarkRead: { item in markRead(item) },
                    onMarkUnread: { item in markUnread(item) },
                    onArchive: { item in Task { await archive(item) } },
                    onDelete: { item in Task { await delete(item) } },
                    onSnooze: { item, hours in Task { await snooze(item, hours: hours) } },
                    onSnoozeTomorrow: { item in Task { await snoozeTomorrow(item) } },
                    onOpen: { item in onOpen(item) }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Spacer(minLength: 36)

                InboxReaderPane(
                    item: selectedItem,
                    emptyState: filteredItems.isEmpty ? .emptyInbox : .noSelection,
                    onOpen: { item in onOpen(item) },
                    onArchive: { item in Task { await archive(item) } },
                    onSnooze: { item, hours in Task { await snooze(item, hours: hours) } }
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
        .undoToast(undo)
        .task { await reload(selectFirstItem: true) }
        .reloadOnStoreChange {
            Task {
                await registry.invalidateCache()
                await reload(selectFirstItem: false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nexusMarkInboxRead)) { _ in
            Task { await markAllRead() }
        }
        .onChange(of: readItemIDs) { _, _ in onUnreadCountChanged(unreadCount) }
        .sheet(item: $snoozeTarget) { item in
            SnoozePickerSheet(
                item: item,
                onConfirm: { date in
                    snoozeTarget = nil
                    Task { try? await registry.snooze(item, until: date) }
                    Task {
                        await registry.invalidateCache()
                        await reload(selectFirstItem: false)
                    }
                },
                onDismiss: { snoozeTarget = nil }
            )
        }
    }

    var macHeaderBand: some View {
        HStack(spacing: DS.Space.s) {
            Spacer()
            Button("Mark all read") { Task { await markAllRead() } }
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .buttonStyle(.plain)
            Divider().frame(height: 14)
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
            BulkAction(label: "Read", systemImage: "envelope.open") {
                let ids = Array(selection.selectedIDs)
                readItemIDs.formUnion(ids)
                readStateStore.save(readItemIDs)
                selection.exitSelection()
                onUnreadCountChanged(unreadCount)
            },
            BulkAction(label: "Snooze 1h", systemImage: "moon.zzz") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) }
                selection.exitSelection()
                Task { for item in selected { await snooze(item, hours: 1) } }
            },
            BulkAction(label: "Archive", systemImage: "archivebox") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) }
                selection.exitSelection()
                Task { for item in selected { await archive(item) } }
            },
            BulkAction(label: "Delete", systemImage: "trash", role: .destructive) {
                let selected = items.filter { selection.selectedIDs.contains($0.id) }
                selection.exitSelection()
                Task {
                    for item in selected { try? await registry.delete(item) }
                    await registry.invalidateCache()
                    await reload(selectFirstItem: false)
                    onUnreadCountChanged(unreadCount)
                    let count = selected.count
                    undo.show(message: "Deleted \(count)") {
                        Task {
                            for item in selected { try? await registry.restore(item) }
                            await registry.invalidateCache()
                            await reload(selectFirstItem: false)
                        }
                    }
                }
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
        .undoToast(undo)
        .task { await reload(selectFirstItem: false) }
        // Pull-to-refresh means "force fresh": invalidate so sources whose data
        // can change without a ModelContext.didSave re-query.
        .refreshable {
            await registry.invalidateCache()
            await reload(selectFirstItem: false)
        }
        .reloadOnStoreChange {
            Task {
                await registry.invalidateCache()
                await reload(selectFirstItem: false)
            }
        }
        .sheet(item: $snoozeTarget) { item in
            SnoozePickerSheet(
                item: item,
                onConfirm: { date in
                    snoozeTarget = nil
                    Task { try? await registry.snooze(item, until: date) }
                    Task {
                        await registry.invalidateCache()
                        await reload(selectFirstItem: false)
                    }
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
            Button("Mark all read") { Task { await markAllRead() } }
                .font(DS.FontToken.button)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .buttonStyle(.plain)
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
            BulkAction(label: "Read", systemImage: "envelope.open") {
                let ids = Array(selection.selectedIDs)
                readItemIDs.formUnion(ids)
                readStateStore.save(readItemIDs)
                selection.exitSelection()
                onUnreadCountChanged(unreadCount)
            },
            BulkAction(label: "Snooze 1h", systemImage: "moon.zzz") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) }
                selection.exitSelection()
                Task { for item in selected { await snooze(item, hours: 1) } }
            },
            BulkAction(label: "Archive", systemImage: "archivebox") {
                let selected = items.filter { selection.selectedIDs.contains($0.id) }
                selection.exitSelection()
                Task { for item in selected { await archive(item) } }
            },
            BulkAction(label: "Delete", systemImage: "trash", role: .destructive) {
                let selected = items.filter { selection.selectedIDs.contains($0.id) }
                selection.exitSelection()
                Task {
                    for item in selected { try? await registry.delete(item) }
                    await registry.invalidateCache()
                    await reload(selectFirstItem: false)
                    onUnreadCountChanged(unreadCount)
                    let count = selected.count
                    undo.show(message: "Deleted \(count)") {
                        Task {
                            for item in selected { try? await registry.restore(item) }
                            await registry.invalidateCache()
                            await reload(selectFirstItem: false)
                        }
                    }
                }
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
                    description: Text("New mentions, digests, and captured items appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(filteredItems) { item in
                    Button {
                        if selection.isSelecting {
                            withAnimation(DS.Motion.selection) { selection.toggle(id: item.id) }
                        } else {
                            onOpen(item)
                        }
                    } label: {
                        InboxCompactRow(item: item, isUnread: !readItemIDs.contains(item.id))
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
                    .onAppear {
                        if item.id == filteredItems.last?.id { Task { await loadMore() } }
                    }
                    .contextMenu { iosContextMenu(for: item) }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await archive(item) }
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(DS.ColorToken.textSecondary)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            Task { await snooze(item, hours: 1) }
                        } label: {
                            Label("1h", systemImage: "clock")
                        }
                        .tint(DS.ColorToken.textSecondary)
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    @ViewBuilder
    func iosContextMenu(for item: InboxItem) -> some View {
        let isUnread = !readItemIDs.contains(item.id)
        if isUnread {
            Button {
                markRead(item)
            } label: {
                Label("Mark Read", systemImage: "envelope.open")
            }
        } else {
            Button {
                markUnread(item)
            } label: {
                Label("Mark Unread", systemImage: "envelope.badge")
            }
        }
        Button {
            onOpen(item)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        Divider()
        Menu("Snooze") {
            Button {
                Task { await snooze(item, hours: 1) }
            } label: {
                Label("1 Hour", systemImage: "clock")
            }
            Button {
                Task { await snoozeTomorrow(item) }
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
            Button {
                snoozeTarget = item
            } label: {
                Label("Custom\u{2026}", systemImage: "calendar")
            }
        }
        Button {
            Task { await archive(item) }
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            Task { await delete(item) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - iOS compact row

struct InboxCompactRow: View {
    let item: InboxItem
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
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .lineLimit(2)
                }
                if !item.tags.isEmpty {
                    Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                        .font(DS.FontToken.metadata)
                        // Tag metadata sits one ink step below the snippet.
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Snooze picker sheet

/// Minimal date-picker sheet for "Custom snooze". Presented from both platforms
/// when the user picks "Custom\u{2026}" from the context menu. Liquid design language:
/// `presentationBackground(.thinMaterial)` + `LiquidPrimaryButton` confirm.
struct SnoozePickerSheet: View {
    let item: InboxItem
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
