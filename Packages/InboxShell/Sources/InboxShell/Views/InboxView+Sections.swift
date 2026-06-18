import NexusUI
import SwiftUI

// Slice-2 (MP-3.1) data-driven section model + §3 list panel, extracted as a
// sibling preemptively (InboxView.swift was at ~507/600 — the section/list
// rebuild would breach swiftlint `file_length`). Mirrors the established
// `TodayDashboard+DigestData.swift` / `+Standalone.swift` extraction pattern.
//
// Achromatic (§2 LabPalette→NexusColor map): zero hue anywhere incl. comments.
// Visual source of truth: `Lab/InboxPreview.swift` (read-only oracle) +
// MP-2.2 §3 section idiom (binding).

#if os(macOS)

// MARK: - Pure section bucketing (slice-5 unit-tests this)

/// One rendered Inbox section: an oracle eyebrow title + the items that fall
/// into it. Pure data — no view state, no `@MainActor`.
struct InboxSection: Identifiable {
    let id: String
    let title: String
    let items: [InboxItem]
    /// TRUE total for this section's source, independent of how many `items`
    /// the window currently materialized. The count pill renders this so it
    /// reads e.g. "1383" while the list shows only a 50-item page — the
    /// windowing fix must not make the pill undercount.
    let totalCount: Int
}

enum InboxSectionBuilder {
    /// Bucket the already-loaded inbox set into the oracle's fixed 4-section
    /// order, grouping by the EXISTING `InboxItem.sourceID` / derived
    /// `InboxItemCategory` only (read-only — NO new field/schema/query; the
    /// audit's "add groupID/iconName" suggestion is §5-FORBIDDEN, rejected).
    ///
    /// - `sourceID == "tasks.no-date"` → "NO DATE"
    /// - `sourceID == "tasks.snoozed"` → "SNOOZED"
    /// - remaining, `category == .digests` → "E-MAIL"
    /// - remaining, `category == .mentions` → "MENTIONS"
    ///
    /// Section order = oracle order (NO DATE, SNOOZED, E-MAIL, MENTIONS),
    /// enforced by fixed-order iteration (NOT a dictionary). §10/§3: a section
    /// renders ONLY if it has ≥1 item — empty buckets are omitted entirely,
    /// never faked or placeholder-counted. With only `TasksNoDateSource` +
    /// `TasksSnoozedSource` registered today, E-MAIL / MENTIONS simply will
    /// not appear; that is correct, not a bug.
    ///
    /// Pure: inputs → `[InboxSection]`. Independently testable.
    ///
    /// `totalsBySourceID` carries each source's TRUE (uncapped) count so the
    /// section pill reflects the real total while `items` is only the rendered
    /// window. The two source-backed sections (NO DATE / SNOOZED) read their
    /// total from the map; the category-derived sections (E-MAIL / MENTIONS)
    /// have no single backing source, so they fall back to their item count —
    /// correct today because no digest/mention source is registered (those
    /// sections never appear), and those sources, when added, will be small
    /// enough to return their full set unwindowed.
    static func sections(from items: [InboxItem], totalsBySourceID: [String: Int] = [:]) -> [InboxSection] {
        // Items whose sourceID/category map to none of the 4 oracle sections
        // (e.g. a future `.people` source, or an orphan `.tasks` item from an
        // unregistered source) have no destination and are dropped here. With
        // the two registered task sources this branch cannot fire today.
        let noDate = items.filter { $0.sourceID == "tasks.no-date" }
        let snoozed = items.filter { $0.sourceID == "tasks.snoozed" }
        let rest = items.filter { $0.sourceID != "tasks.no-date" && $0.sourceID != "tasks.snoozed" }
        let mail = rest.filter { $0.category == .digests }
        let mentions = rest.filter { $0.category == .mentions }

        let ordered: [InboxSection] = [
            InboxSection(
                id: "tasks.no-date",
                title: "NO DATE",
                items: noDate,
                totalCount: totalsBySourceID["tasks.no-date"] ?? noDate.count
            ),
            InboxSection(
                id: "tasks.snoozed",
                title: "SNOOZED",
                items: snoozed,
                totalCount: totalsBySourceID["tasks.snoozed"] ?? snoozed.count
            ),
            InboxSection(id: "digests", title: "E-MAIL", items: mail, totalCount: mail.count),
            InboxSection(id: "mentions", title: "MENTIONS", items: mentions, totalCount: mentions.count),
        ]
        return ordered.filter { !$0.items.isEmpty }
    }
}

// MARK: - Layout geometry (Inbox oracle — NOT §3's single-column 620)

enum InboxLayout {
    /// Oracle RIGHT reader pane fixed width. The LEFT list panel no longer caps
    /// at a narrow 560 measure — it fills the space up to this reader pane
    /// (left-aligned with the chrome) so there is no dead centre void.
    static let readerWidth: CGFloat = 380
}

// MARK: - List panel (§3 section idiom)

struct InboxListPanel: View {
    let items: [InboxItem]
    let error: String?
    /// Per-source true totals so each section pill reads the real count while
    /// the list only renders the current window.
    let totalsBySourceID: [String: Int]
    @Binding var readItemIDs: Set<UUID>
    @Binding var selectedItem: InboxItem?
    /// Multi-select model threaded down from InboxView so rows can enter
    /// selection mode and the BulkActionBar at the parent level reacts.
    let selection: SelectionModel<UUID>
    /// Fired when the scroll nears the bottom — grows the window page so the
    /// no-date section pages in on scroll instead of materializing ~1383 rows.
    let onReachEnd: () -> Void
    // Row action callbacks wired to InboxView's private helpers.
    let onMarkRead: (InboxItem) -> Void
    let onMarkUnread: (InboxItem) -> Void
    let onArchive: (InboxItem) -> Void
    let onDelete: (InboxItem) -> Void
    let onSnooze: (InboxItem, Int) -> Void
    let onSnoozeTomorrow: (InboxItem) -> Void
    let onOpen: (InboxItem) -> Void

    private var sections: [InboxSection] {
        InboxSectionBuilder.sections(from: items, totalsBySourceID: totalsBySourceID)
    }

    var body: some View {
        ScrollView {
            // Error / items-empty branches keep their slice-1 / §5-contract
            // English placeholders untouched (slice 4 owns the achievement
            // "Inbox czysty" state). Slice 2 only restructures the populated
            // sections + the reader's neutral nothing-selected state.
            if error != nil {
                InboxPanelEmptyState(
                    title: "Couldn't load the Inbox",
                    subtitle: "Try refreshing in a moment.",
                    systemImage: "exclamationmark.triangle"
                )
            } else if items.isEmpty {
                InboxPanelEmptyState(
                    title: "Inbox is empty",
                    subtitle: "New mentions, digests, and captured items appear here.",
                    systemImage: "tray"
                )
            } else {
                VStack(alignment: .leading, spacing: 26) {
                    ForEach(sections) { section in
                        InboxSectionView(
                            section: section,
                            readItemIDs: $readItemIDs,
                            selectedItem: $selectedItem,
                            selection: selection,
                            onMarkRead: onMarkRead,
                            onMarkUnread: onMarkUnread,
                            onArchive: onArchive,
                            onDelete: onDelete,
                            onSnooze: onSnooze,
                            onSnoozeTomorrow: onSnoozeTomorrow,
                            onOpen: onOpen
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Leading gutter = the app-wide chrome gutter (18), matching the
                // filter-tab band in the toolbar above (was 26 — list hung 8pt right).
                .padding(.leading, 18)
                .padding(.trailing, 12)
                // Top gap so the first section header isn't glued to the topbar
                // (matches the reader pane's top inset / the Today list's 24).
                .padding(.top, 22)
                .padding(.bottom, 24)
            }
        }
        .scrollContentBackground(.hidden)
        // Reliable scroll-to-grow for the non-lazy section stack: `.onAppear` on
        // the last row is unreliable here (a plain `VStack` in a `ScrollView`
        // doesn't re-fire `onAppear` for off-screen rows on scroll), so observe
        // the scroll geometry instead and grow when the offset crosses into the
        // bottom prefetch zone. The `false → true` edge (wasNear → isNear) fires
        // `onReachEnd` once per approach; with a tall list it stays false at
        // entry (no premature grow), and `loadMore` itself guards the end.
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - Self.prefetchZone
        } action: { wasNear, isNear in
            if isNear && !wasNear { onReachEnd() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Distance from the bottom (≈ a dozen rows) at which the next page prefetches.
    private static let prefetchZone: CGFloat = 600
}

// MARK: - Section (Liquid idiom — caption eyebrow + count pill + staggered rows)

struct InboxSectionView: View {
    let section: InboxSection
    @Binding var readItemIDs: Set<UUID>
    @Binding var selectedItem: InboxItem?
    let selection: SelectionModel<UUID>
    let onMarkRead: (InboxItem) -> Void
    let onMarkUnread: (InboxItem) -> Void
    let onArchive: (InboxItem) -> Void
    let onDelete: (InboxItem) -> Void
    let onSnooze: (InboxItem, Int) -> Void
    let onSnoozeTomorrow: (InboxItem) -> Void
    let onOpen: (InboxItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(section.title)
                    .font(DS.FontToken.caption)
                    .tracking(1.4)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                LiquidPill("\(section.totalCount)", color: DS.ColorToken.statusNeutral)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    InboxPanelRow(
                        item: item,
                        isUnread: !readItemIDs.contains(item.id),
                        isSelected: selectedItem?.id == item.id
                    ) {
                        if selection.isSelecting {
                            withAnimation(DS.Motion.selection) { selection.toggle(id: item.id) }
                        } else {
                            selectedItem = item
                            readItemIDs.insert(item.id)
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
        }
    }

    @ViewBuilder
    private func macContextMenu(for item: InboxItem) -> some View {
        let isUnread = !readItemIDs.contains(item.id)
        if isUnread {
            Button {
                onMarkRead(item)
            } label: {
                Label("Mark Read", systemImage: "envelope.open")
            }
        } else {
            Button {
                onMarkUnread(item)
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
                onSnooze(item, 1)
            } label: {
                Label("1 Hour", systemImage: "clock")
            }
            Button {
                onSnoozeTomorrow(item)
            } label: {
                Label("Tomorrow", systemImage: "sunrise")
            }
        }
        Button {
            onArchive(item)
        } label: {
            Label("Archive", systemImage: "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            onDelete(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Row (slice-3 — oracle InboxRowView shape, achromatic §2 map)

struct InboxPanelRow: View {
    let item: InboxItem
    let isUnread: Bool
    let isSelected: Bool
    let action: () -> Void

    @State private var hover = false

    var body: some View {
        // Plain tappable row (NOT a Button): a SwiftUI Button nested in a
        // LazyVStack + `.selectable` + `.contextMenu` swallows its action on
        // macOS, so the row never toggled in select mode. `.onTapGesture`
        // fires reliably (same pattern as the working Tasks list).
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isUnread ? DS.ColorToken.accentPrimary : Color.clear)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Image(systemName: item.nexusInboxSourceIcon)
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
                    Text(item.nexusInboxRelativeTime)
                        .font(DS.FontToken.metadata)
                        .monospacedDigit()
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
                Text(item.body ?? "")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .lineLimit(1)
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

struct InboxPanelEmptyState: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        // Liquid empty-state idiom (03_COMPONENTS.md §Empty): calm glyph + one
        // line + quiet subtitle; centered in the list panel's empty space.
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
