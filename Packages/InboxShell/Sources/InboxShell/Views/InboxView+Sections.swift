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
    static func sections(from items: [InboxItem]) -> [InboxSection] {
        // Items whose sourceID/category map to none of the 4 oracle sections
        // (e.g. a future `.people` source, or an orphan `.tasks` item from an
        // unregistered source) have no destination and are dropped here. With
        // the two registered task sources this branch cannot fire today.
        let noDate = items.filter { $0.sourceID == "tasks.no-date" }
        let snoozed = items.filter { $0.sourceID == "tasks.snoozed" }
        let rest = items.filter {
            $0.sourceID != "tasks.no-date" && $0.sourceID != "tasks.snoozed"
        }
        let mail = rest.filter { $0.category == .digests }
        let mentions = rest.filter { $0.category == .mentions }

        let ordered: [InboxSection] = [
            InboxSection(id: "tasks.no-date", title: "NO DATE", items: noDate),
            InboxSection(id: "tasks.snoozed", title: "SNOOZED", items: snoozed),
            InboxSection(id: "digests", title: "E-MAIL", items: mail),
            InboxSection(id: "mentions", title: "MENTIONS", items: mentions),
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
    @Binding var readItemIDs: Set<UUID>
    @Binding var selectedItem: InboxItem?

    private var sections: [InboxSection] {
        InboxSectionBuilder.sections(from: items)
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
                            selectedItem: $selectedItem
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Section (Liquid idiom — caption eyebrow + count pill + staggered rows)

struct InboxSectionView: View {
    let section: InboxSection
    @Binding var readItemIDs: Set<UUID>
    @Binding var selectedItem: InboxItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(section.title)
                    .font(DS.FontToken.caption)
                    .tracking(1.4)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                LiquidPill("\(section.items.count)", color: DS.ColorToken.statusNeutral)
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
                        selectedItem = item
                        readItemIDs.insert(item.id)
                    }
                    .nexusAppear(index)
                }
            }
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
        Button(action: action) {
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
        }
        .buttonStyle(.plain)
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
