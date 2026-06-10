import NexusUI
import SwiftUI

public enum InboxReaderEmptyState: Sendable {
    case noSelection
    case emptyInbox
}

public struct InboxReaderPane: View {
    public let item: InboxItem?
    public let emptyState: InboxReaderEmptyState
    public let onOpen: @MainActor (InboxItem) -> Void
    public let onArchive: @MainActor (InboxItem) -> Void
    public let onSnooze: @MainActor (InboxItem, Int) -> Void

    public init(
        item: InboxItem?,
        emptyState: InboxReaderEmptyState = .noSelection,
        onOpen: @escaping @MainActor (InboxItem) -> Void,
        onArchive: @escaping @MainActor (InboxItem) -> Void,
        onSnooze: @escaping @MainActor (InboxItem, Int) -> Void
    ) {
        self.item = item
        self.emptyState = emptyState
        self.onOpen = onOpen
        self.onArchive = onArchive
        self.onSnooze = onSnooze
    }

    public var body: some View {
        if let item {
            // ScrollView added here at the call site so a long `item.body`
            // doesn't clip — the oracle sample uses fixed text; production
            // content is unbounded. `populated(_:)` itself is a pure
            // VStack → glass builder.
            ScrollView {
                populated(item)
            }
            .scrollContentBackground(.hidden)
            .readerPaneSurface()
        } else {
            // Slice-2: neutral "nothing selected" state to the Inbox-oracle
            // §9 idiom. `LabEmptyState(tone: .neutral)` → dashed circle 28×28
            // (NO glyph — the 34×34 + glyph form is the .achievement tone;
            // see self-review note), 380-wide centred, wrapped in the flat
            // Linear reader surface (`readerPaneSurface()` → `Background.raised`
            // + one hairline stroke + `s1` shadow). Achievement full-inbox
            // state is SLICE 4.
            neutralEmptyState
                .readerPaneSurface()
        }
    }

    private var neutralEmptyState: some View {
        VStack(spacing: 0) {
            Circle()
                .stroke(
                    DS.ColorToken.strokeStrong,
                    style: StrokeStyle(lineWidth: 1.3, dash: [2, 3.5])
                )
                .frame(width: 28, height: 28)
                .frame(height: 38)
                .padding(.bottom, 18)
            Text(emptyState.title)
                .font(DS.FontToken.section)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
            if let subtitle = emptyState.subtitle {
                Text(subtitle)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .nexusAppear(0)
    }

    // MARK: – Populated reader
    // Structure mirrors Lab/InboxPreview.swift `reader` (oracle).
    // Inner structure, spacing, and padding match the oracle exactly. Scroll
    // wrapping for unbounded content is handled at the `body` call site, not
    // here — `populated(_:)` is a pure VStack → glass builder.

    private func populated(_ item: InboxItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow(item)
            titleText(item)
            bodyText(item)
            if !item.tags.isEmpty {
                tagRow(item)
            }
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(height: 1)
                .padding(.bottom, 18)
            actionPills(item)
            // §10: AI-proposal block omitted — no backend reachable from this surface
            // (deferred follow-up, tracked in counts §12).
        }
    }

    // 1. Eyebrow row: icon · source label · Spacer · age
    private func eyebrowRow(_ item: InboxItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.nexusInboxSourceIcon)
                .font(.system(size: 10))
                .foregroundStyle(DS.ColorToken.textMuted)
            Text(item.nexusInboxSourceLabel)
                .font(DS.FontToken.caption)
                .tracking(1.6)
                .foregroundStyle(DS.ColorToken.textMuted)
            Spacer()
            Text(item.nexusInboxRelativeTime)
                .font(DS.FontToken.metadata)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
        .padding(.bottom, 16)
    }

    // 2. Title
    private func titleText(_ item: InboxItem) -> some View {
        Text(item.title)
            .font(DS.FontToken.title)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }

    // 3. Body — always rendered; empty string for bodyless items (§10: no placeholder copy)
    private func bodyText(_ item: InboxItem) -> some View {
        Text(item.body ?? "")
            .font(DS.FontToken.body)
            .foregroundStyle(DS.ColorToken.textSecondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 18)
    }

    // 4. Tag chips — rendered only when item.tags is non-empty
    private func tagRow(_ item: InboxItem) -> some View {
        HStack(spacing: 8) {
            ForEach(item.tags, id: \.self) { tag in
                LiquidPill(tag, color: DS.ColorToken.statusNeutral)
            }
        }
        .padding(.bottom, 22)
    }

    // 6. Action pills wired to the real closures
    private func actionPills(_ item: InboxItem) -> some View {
        HStack(spacing: 9) {
            LiquidPrimaryButton("Send to Tasks", systemImage: "arrow.right.circle") {
                onOpen(item)
            }
            ReaderGhostButton("Snooze 1d", systemImage: "moon.zzz") {
                onSnooze(item, 24)
            }
            ReaderGhostButton("Archive", systemImage: "archivebox") {
                onArchive(item)
            }
        }
        .padding(.bottom, 16)
    }
}

/// Secondary reader action: a quiet glass button (soft fill, hairline stroke,
/// hover wash) one emphasis step below ``LiquidPrimaryButton`` — the
/// 03_COMPONENTS.md §IconButton fill ladder applied to a labelled control.
private struct ReaderGhostButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(DS.FontToken.button)
            .foregroundStyle(hovering ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
            .padding(.horizontal, DS.Space.m)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0x10 / 255.0) : DS.ColorToken.glassSoft)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}

extension InboxReaderEmptyState {
    fileprivate var title: String {
        switch self {
        case .noSelection:
            return "No preview"
        case .emptyInbox:
            return "Nothing to review"
        }
    }

    fileprivate var subtitle: String? {
        switch self {
        case .noSelection:
            return "Select an item to read it here."
        case .emptyInbox:
            return nil
        }
    }
}

private struct InboxReaderPaneSurface: ViewModifier {
    func body(content: Content) -> some View {
        // Liquid reader surface: the inspector-grade `.sidebar` glass (denser
        // tint than `.card`) so the reading pane reads as its own pane of
        // glass beside the list, per the reference boards' right panes.
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlass(.sidebar, radius: DS.Radius.l)
    }
}

extension View {
    fileprivate func readerPaneSurface() -> some View {
        modifier(InboxReaderPaneSurface())
    }
}
