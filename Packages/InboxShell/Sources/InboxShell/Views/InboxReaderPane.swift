import NexusUI
import SwiftUI

public enum InboxReaderEmptyState: Sendable {
    case noSelection
    case emptyInbox
}

public struct InboxReaderPane: View {
    public let item: FeedItem?
    public let emptyState: InboxReaderEmptyState
    public let onOpen: @MainActor (FeedItem) -> Void
    public let onDismiss: @MainActor (FeedItem) -> Void
    public let onSnooze: @MainActor (FeedItem, Int) -> Void

    public init(
        item: FeedItem?,
        emptyState: InboxReaderEmptyState = .noSelection,
        onOpen: @escaping @MainActor (FeedItem) -> Void,
        onDismiss: @escaping @MainActor (FeedItem) -> Void,
        onSnooze: @escaping @MainActor (FeedItem, Int) -> Void
    ) {
        self.item = item
        self.emptyState = emptyState
        self.onOpen = onOpen
        self.onDismiss = onDismiss
        self.onSnooze = onSnooze
    }

    public var body: some View {
        if let item {
            ScrollView {
                populated(item)
            }
            .scrollContentBackground(.hidden)
            .readerPaneSurface()
        } else {
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

    // MARK: - Populated reader

    private func populated(_ item: FeedItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow(item)
            titleText(item)
            bodyText(item)
            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(height: 1)
                .padding(.bottom, 18)
            actionPills(item)
        }
    }

    // 1. Eyebrow row: icon · stream label · Spacer · age (suppressed for bridge)
    private func eyebrowRow(_ item: FeedItem) -> some View {
        HStack(spacing: 7) {
            Image(systemName: item.iconName)
                .font(.system(size: 10))
                .foregroundStyle(DS.ColorToken.textMuted)
            Text(item.stream.streamLabel.uppercased())
                .font(DS.FontToken.caption)
                .tracking(1.6)
                .foregroundStyle(DS.ColorToken.textMuted)
            Spacer()
            if item.stream != .bridge {
                Text(item.nexusInboxRelativeTime)
                    .font(DS.FontToken.metadata)
                    .monospacedDigit()
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
        .padding(.bottom, 16)
    }

    // 2. Title
    private func titleText(_ item: FeedItem) -> some View {
        Text(item.title)
            .font(DS.FontToken.title)
            .foregroundStyle(DS.ColorToken.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }

    // 3. Body / subtitle
    private func bodyText(_ item: FeedItem) -> some View {
        Text(item.subtitle ?? "")
            .font(DS.FontToken.body)
            .foregroundStyle(DS.ColorToken.textSecondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 18)
    }

    // 4. Action pills — bridge: Open only; others: Open + Snooze + Dismiss
    private func actionPills(_ item: FeedItem) -> some View {
        HStack(spacing: 9) {
            LiquidPrimaryButton("Open", systemImage: "arrow.up.right.circle") {
                onOpen(item)
            }
            if item.stream != .bridge {
                ReaderGhostButton("Snooze", systemImage: "moon.zzz") {
                    onSnooze(item, 24)
                }
                ReaderGhostButton("Dismiss", systemImage: "xmark.circle") {
                    onDismiss(item)
                }
            }
        }
        .padding(.bottom, 16)
    }
}

/// Secondary reader action: a quiet glass button.
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
            HStack(spacing: DS.Space.xs) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
            }
            .font(DS.FontToken.button)
            .fixedSize(horizontal: true, vertical: false)
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
        .buttonStyle(NexusPressableButtonStyle())
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
