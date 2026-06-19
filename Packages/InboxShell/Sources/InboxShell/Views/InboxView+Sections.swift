import NexusUI
import SwiftUI

// Flat-list panel and row — replaces the sectioned InboxSectionBuilder layout.
// Renders filteredItems directly (bridge row first via .distantFuture createdAt,
// then agent/meeting newest-first from the registry). No windowing; no sections.

#if os(macOS)

// MARK: - Layout geometry

enum InboxLayout {
    /// Oracle RIGHT reader pane fixed width.
    static let readerWidth: CGFloat = 380
}

// MARK: - List panel

struct InboxListPanel: View {
    let items: [FeedItem]
    let error: String?
    @Binding var selectedItem: FeedItem?
    let selection: SelectionModel<String>
    let onOpen: (FeedItem) -> Void
    let onDismiss: (FeedItem) -> Void
    let onSnooze: (FeedItem, Int) -> Void
    let onCustomSnooze: (FeedItem) -> Void

    var body: some View {
        ScrollView {
            if error != nil {
                InboxPanelEmptyState(
                    title: "Couldn't load the Inbox",
                    subtitle: "Try refreshing in a moment.",
                    systemImage: "exclamationmark.triangle"
                )
            } else if items.isEmpty {
                InboxPanelEmptyState(
                    title: "Inbox is empty",
                    subtitle: "New agent insights and meeting summaries appear here.",
                    systemImage: "tray"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        InboxPanelRow(
                            item: item,
                            isUnread: item.seenAt == nil && item.stream != .bridge,
                            isSelected: selectedItem?.id == item.id
                        ) {
                            if selection.isSelecting {
                                withAnimation(DS.Motion.selection) { selection.toggle(id: item.id) }
                            } else {
                                selectedItem = item
                                onOpen(item)
                            }
                        }
                        .nexusAppear(index)
                        .selectable(
                            isSelecting: selection.isSelecting,
                            isSelected: selection.isSelected(id: item.id),
                            onToggle: { selection.toggle(id: item.id) }
                        )
                        .contextMenu {
                            macContextMenu(for: item)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 18)
                .padding(.trailing, 12)
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func macContextMenu(for item: FeedItem) -> some View {
        Button {
            onOpen(item)
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        if item.stream != .bridge {
            Divider()
            Menu("Snooze") {
                Button {
                    onSnooze(item, 1)
                } label: {
                    Label("1 Hour", systemImage: "clock")
                }
                Button {
                    onSnooze(item, 24)
                } label: {
                    Label("Tomorrow", systemImage: "sunrise")
                }
                Button {
                    onCustomSnooze(item)
                } label: {
                    Label("Custom\u{2026}", systemImage: "calendar")
                }
            }
            Button(role: .destructive) {
                onDismiss(item)
            } label: {
                Label("Dismiss", systemImage: "xmark.circle")
            }
        }
    }
}

// MARK: - Row

struct InboxPanelRow: View {
    let item: FeedItem
    let isUnread: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isUnread ? DS.ColorToken.accentPrimary : Color.clear)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Image(systemName: item.iconName)
                .font(.system(size: 11))
                .foregroundStyle(DS.ColorToken.textMuted)
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(isUnread ? DS.FontToken.bodyStrong : DS.FontToken.body)
                        .foregroundStyle(isUnread ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 12)
                    if item.stream != .bridge {
                        Text(item.nexusInboxRelativeTime)
                            .font(DS.FontToken.metadata)
                            .monospacedDigit()
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(
                    isSelected
                        ? DS.ColorToken.glassSelected
                        : (hover ? Color.white.opacity(0.04) : Color.clear)
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(isSelected ? DS.ColorToken.strokeHairline : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onHover { value in
            withAnimation(DS.Motion.hover) { hover = value }
        }
        .onTapGesture { action() }
    }
}

// MARK: - Empty state

struct InboxPanelEmptyState: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: DS.Space.m) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
            Text(title)
                .font(DS.FontToken.section)
                .foregroundStyle(DS.ColorToken.textSecondary)
            Text(subtitle)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

#endif

// MARK: - FeedStream presentation helpers

extension FeedStream {
    /// Human-readable label for eyebrow / source rows.
    var streamLabel: String {
        switch self {
        case .agent: return "Agent"
        case .meeting: return "Meetings"
        case .bridge: return "Tasks"
        }
    }
}

extension FeedItem {
    /// Relative-time string for rows; suppressed for bridge rows.
    var nexusInboxRelativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }
}
