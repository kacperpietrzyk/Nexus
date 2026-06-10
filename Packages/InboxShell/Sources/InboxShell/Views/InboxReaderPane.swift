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
                    NexusColor.Text.disabled,
                    style: StrokeStyle(lineWidth: 1.3, dash: [2, 3.5])
                )
                .frame(width: 28, height: 28)
                .frame(height: 38)
                .padding(.bottom, 18)
            Text(emptyState.title)
                .nexusType(.h3)
                .foregroundStyle(NexusColor.Text.secondary)
                .multilineTextAlignment(.center)
            if let subtitle = emptyState.subtitle {
                Text(subtitle)
                    .nexusType(.meta)
                    .foregroundStyle(NexusColor.Text.muted)
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
                .fill(NexusColor.Line.hairline)
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
                .foregroundStyle(NexusColor.Text.muted)
            Text(item.nexusInboxSourceLabel)
                .font(NexusType.metaMono)
                .tracking(1.6)
                .foregroundStyle(NexusColor.Text.muted)
            Spacer()
            Text(item.nexusInboxRelativeTime)
                .font(NexusType.metaMono)
                .foregroundStyle(NexusColor.Text.disabled)
        }
        .padding(.bottom, 16)
    }

    // 2. Title
    private func titleText(_ item: InboxItem) -> some View {
        Text(item.title)
            .font(Font.custom("Inter-SemiBold", size: 19))
            .foregroundStyle(NexusColor.Text.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }

    // 3. Body — always rendered; empty string for bodyless items (§10: no placeholder copy)
    private func bodyText(_ item: InboxItem) -> some View {
        Text(item.body ?? "")
            .nexusType(.bodySmall)
            .foregroundStyle(NexusColor.Text.tertiary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 18)
    }

    // 4. Tag chips — rendered only when item.tags is non-empty
    private func tagRow(_ item: InboxItem) -> some View {
        HStack(spacing: 8) {
            ForEach(item.tags, id: \.self) { tag in
                NexusChip(tag, tone: .neutral)
            }
        }
        .padding(.bottom, 22)
    }

    // 6. Action pills wired to the real closures
    private func actionPills(_ item: InboxItem) -> some View {
        HStack(spacing: 9) {
            NexusButton(
                variant: .primary,
                size: .sm,
                action: { onOpen(item) },
                label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.right.circle")
                        Text("Send to Tasks")
                    }
                }
            )
            NexusButton(
                variant: .default,
                size: .sm,
                action: { onSnooze(item, 24) },
                label: {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz")
                        Text("Snooze 1d")
                    }
                }
            )
            NexusButton(
                variant: .default,
                size: .sm,
                action: { onArchive(item) },
                label: {
                    HStack(spacing: 5) {
                        Image(systemName: "archivebox")
                        Text("Archive")
                    }
                }
            )
        }
        .padding(.bottom, 16)
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
        // Liquid re-skin (container level): the liquid glass card recipe
        // replaces the opaque `Background.raised` slab + manual Line.regular
        // stroke + s1 shadow, so the reader pane sits on the shell's glass
        // instead of reading as a black panel. Inner structure unchanged.
        content
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlass(.card, radius: NexusRadius.r3)
    }
}

extension View {
    fileprivate func readerPaneSurface() -> some View {
        modifier(InboxReaderPaneSurface())
    }
}
