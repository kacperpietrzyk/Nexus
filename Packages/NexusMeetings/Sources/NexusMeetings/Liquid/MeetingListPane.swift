import Foundation
import NexusUI
import SwiftUI

#if os(macOS)

/// Honest source badge for a meeting row / detail header: an SF Symbol + a
/// label derived from the REAL `detectionSource` / `appBundleID` fields. Known
/// conferencing bundle ids map to their app name with a generic video glyph —
/// never a fake app logo.
enum MeetingSourceBadge {
    /// `(bundle-id fragment, display name)` for the conferencing apps the
    /// detector actually watches. Matched by substring on the lowercased id.
    private static let knownApps: [(fragment: String, name: String)] = [
        ("zoom", "Zoom"),
        ("teams", "Microsoft Teams"),
        ("webex", "Webex"),
        ("facetime", "FaceTime"),
        ("slack", "Slack"),
        ("meet", "Google Meet"),
    ]

    static func systemImage(for meeting: Meeting) -> String {
        switch MeetingDetectionSource(rawValue: meeting.detectionSource) {
        case .imported: return "square.and.arrow.down"
        case .manual: return "mic"
        default:
            return appName(for: meeting.appBundleID) != nil ? "video" : "waveform"
        }
    }

    static func label(for meeting: Meeting) -> String {
        if let name = appName(for: meeting.appBundleID) { return name }
        switch MeetingDetectionSource(rawValue: meeting.detectionSource) {
        case .imported: return "Imported"
        case .manual: return "Manual recording"
        default: return "Auto-detected"
        }
    }

    private static func appName(for bundleID: String?) -> String? {
        guard let bundleID = bundleID?.lowercased(), !bundleID.isEmpty else { return nil }
        return knownApps.first { bundleID.contains($0.fragment) }?.name
    }
}

/// Shared date/time formatters for the Meetings screen. Explicit `en_US`
/// (English UI rule — the system locale may be pl_PL).
enum LiquidMeetingsFormat {
    static let time: DateFormatter = makeFormatter("h:mm a")
    static let dayAndTime: DateFormatter = makeFormatter("MMM d · h:mm a")
    static let fullDate: DateFormatter = makeFormatter("EEEE, MMM d, yyyy")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = format
        return formatter
    }

    /// `10:00–10:50 AM` style range from the real start + duration; start
    /// time only when the meeting has no recorded duration.
    static func timeRange(start: Date, durationSec: Int) -> String {
        guard durationSec > 0 else { return time.string(from: start) }
        let end = start.addingTimeInterval(TimeInterval(durationSec))
        return "\(time.string(from: start))–\(time.string(from: end))"
    }
}

/// Meeting list pane (spec §Meeting list): search field, Today / Yesterday /
/// This Week / Earlier groups, rows with title + time + source glyph. The
/// active meeting gets the glass selected state with an accent leading line.
/// Supports multi-select via long-press: `SelectionModel` + `BulkActionBar`
/// for bulk Pin and bulk Delete-with-undo.
struct MeetingListPane: View {

    @Bindable var model: LiquidMeetingsModel
    let selectedID: UUID?
    let onSelect: (UUID) -> Void
    let onSearchChanged: () -> Void
    let onTogglePin: (Meeting) -> Void
    /// Copy summary as Markdown to pasteboard.
    let onCopySummary: (Meeting) -> Void
    /// Re-run summary generation through the pipeline (seam: callers that have
    /// no live pipeline pass a no-op).
    let onRerunSummary: (Meeting) -> Void
    /// Hard-delete the meeting (with audio cleanup).
    let onDelete: (Meeting) -> Void

    // Multi-select state owned here; the bulk bar reads it.
    @State private var selection = SelectionModel<UUID>()
    @State private var undo = UndoController()
    private let composition: MeetingsComposition

    init(
        model: LiquidMeetingsModel,
        composition: MeetingsComposition,
        selectedID: UUID?,
        onSelect: @escaping (UUID) -> Void,
        onSearchChanged: @escaping () -> Void,
        onTogglePin: @escaping (Meeting) -> Void,
        onCopySummary: @escaping (Meeting) -> Void,
        onRerunSummary: @escaping (Meeting) -> Void,
        onDelete: @escaping (Meeting) -> Void
    ) {
        self.model = model
        self.composition = composition
        self.selectedID = selectedID
        self.onSelect = onSelect
        self.onSearchChanged = onSearchChanged
        self.onTogglePin = onTogglePin
        self.onCopySummary = onCopySummary
        self.onRerunSummary = onRerunSummary
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.xs) {
                searchField
                LiquidIconButton(
                    systemImage: selection.isSelecting ? "xmark.circle" : "checkmark.circle",
                    accessibilityLabel: selection.isSelecting ? "Cancel selection" : "Select meetings"
                ) {
                    withAnimation(DS.Motion.selection) {
                        if selection.isSelecting { selection.exitSelection() } else { selection.enterSelection() }
                    }
                }
            }

            if model.meetings.isEmpty {
                LiquidEmptyState(
                    systemImage: "magnifyingglass",
                    message: "No meetings match your search."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.xs) {
                        ForEach(LiquidMeetingsModel.grouped(model.meetings), id: \.bucket) { group in
                            section(group.bucket, meetings: group.meetings)
                        }
                    }
                    .padding(.bottom, DS.Space.m)
                }
            }
        }
        .padding(DS.Space.m)
        .frame(maxHeight: .infinity, alignment: .top)
        .liquidGlass(.sidebar, radius: DS.Radius.l)
        .overlay(alignment: .bottom) {
            BulkActionBar(
                model: selection,
                allIDs: model.meetings.map(\.id),
                actions: [
                    BulkAction(label: "Pin", systemImage: "star") {
                        model.pinAll(selection.selectedIDs, composition: composition)
                        selection.exitSelection()
                    },
                    BulkAction(label: "Delete", systemImage: "trash", role: .destructive) {
                        let ids = selection.selectedIDs
                        let count = ids.count
                        let restore = model.deleteAll(ids, composition: composition)
                        selection.exitSelection()
                        undo.show(message: "Deleted \(count) \(count == 1 ? "meeting" : "meetings")", icon: "trash") {
                            restore()
                        }
                    },
                ]
            )
        }
        .undoToast(undo)
        // Global ⌘A + palette "Select All Items": select every visible meeting.
        .selectAllCommandTarget(in: selection, ids: model.meetings.map(\.id))
        .onReceive(NotificationCenter.default.publisher(for: .nexusSelectAllActiveSurface)) { _ in
            selection.enterSelection()
            selection.selectAll(model.meetings.map(\.id))
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
            TextField("Search meetings…", text: $model.searchQuery)
                .textFieldStyle(.plain)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .onChange(of: model.searchQuery) { _, _ in onSearchChanged() }
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                // macOS: a light translucent inset so the field reads as glass,
                // not a near-black slab on the light pane. iOS keeps the sunken fill.
                #if os(macOS)
            .fill(Color.white.opacity(0.06))
                #else
            .fill(DS.ColorToken.backgroundSunken.opacity(0.6))
                #endif
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func section(_ bucket: LiquidMeetingsModel.Bucket, meetings: [Meeting]) -> some View {
        Text(bucket.rawValue.uppercased())
            .font(DS.FontToken.caption)
            .kerning(0.6)
            .foregroundStyle(DS.ColorToken.textMuted)
            .padding(.horizontal, DS.Space.xs)
            .padding(.top, DS.Space.s)

        ForEach(meetings, id: \.id) { meeting in
            MeetingListRow(
                meeting: meeting,
                bucket: bucket,
                isSelected: meeting.id == selectedID,
                action: { onSelect(meeting.id) },
                onTogglePin: { onTogglePin(meeting) },
                onCopySummary: { onCopySummary(meeting) },
                onRerunSummary: { onRerunSummary(meeting) },
                onDelete: { onDelete(meeting) },
                selection: selection
            )
        }
    }
}

private struct MeetingListRow: View {
    let meeting: Meeting
    let bucket: LiquidMeetingsModel.Bucket
    let isSelected: Bool
    let action: () -> Void
    let onTogglePin: () -> Void
    let onCopySummary: () -> Void
    let onRerunSummary: () -> Void
    let onDelete: () -> Void
    let selection: SelectionModel<UUID>

    @State private var hovering = false

    var body: some View {
        Button {
            // In multi-select mode the row tap toggles selection instead of
            // opening the meeting (the `.selectable` checkmark is presentation
            // only and can't capture the tap).
            if selection.isSelecting {
                withAnimation(DS.Motion.selection) { selection.toggle(id: meeting.id) }
            } else {
                action()
            }
        } label: {
            HStack(alignment: .top, spacing: DS.Space.s) {
                // Accent leading line marks the active meeting (spec §Meeting list).
                Capsule(style: .continuous)
                    .fill(isSelected ? DS.ColorToken.accentPrimary : .clear)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(isSelected ? DS.FontToken.bodyStrong : DS.FontToken.body)
                        .foregroundStyle(
                            isSelected ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary
                        )
                        .lineLimit(1)
                    Text(timeText)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                LiquidPinButton(isPinned: meeting.isPinned, toggle: onTogglePin)
                    .opacity(hovering || meeting.isPinned ? 1 : 0)

                Image(systemName: MeetingSourceBadge.systemImage(for: meeting))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .padding(.top, 2)
                    .accessibilityLabel(MeetingSourceBadge.label(for: meeting))
            }
            .padding(.vertical, DS.Space.xs)
            .padding(.horizontal, DS.Space.xs)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(
                        isSelected
                            ? DS.ColorToken.glassSelected
                            : hovering ? Color.white.opacity(0.04) : .clear
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectable(
            isSelecting: selection.isSelecting,
            isSelected: selection.isSelected(id: meeting.id),
            onToggle: { selection.toggle(id: meeting.id) }
        )
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        .contextMenu {
            Button(meeting.isPinned ? "Unpin from Today" : "Pin to Today") {
                onTogglePin()
            }

            Divider()

            Button {
                onCopySummary()
            } label: {
                Label("Copy Summary as Markdown", systemImage: "doc.on.doc")
            }

            Button {
                onRerunSummary()
            } label: {
                Label("Re-run Summary", systemImage: "arrow.clockwise")
            }
            .disabled(meeting.transcriptText.isEmpty)

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Meeting", systemImage: "trash")
            }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Today/Yesterday rows show the time only (the group header already says
    /// the day); older rows carry the abbreviated date.
    private var timeText: String {
        switch bucket {
        case .today, .yesterday:
            return LiquidMeetingsFormat.time.string(from: meeting.startedAt)
        case .thisWeek, .earlier:
            return LiquidMeetingsFormat.dayAndTime.string(from: meeting.startedAt)
        }
    }
}
#endif
