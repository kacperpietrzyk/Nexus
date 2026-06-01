#if !os(watchOS)
import SwiftUI

public struct NexusTopBar<Trailing: View>: View {
    internal static var searchHeight: CGFloat { 30 }
    internal static var searchMinWidth: CGFloat { 240 }

    public let crumbs: [String]
    public let showSearchPill: Bool
    public let onCmdK: () -> Void
    @ViewBuilder public let trailing: () -> Trailing

    public init(
        crumbs: [String],
        showSearchPill: Bool = true,
        onCmdK: @escaping () -> Void = {},
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.crumbs = crumbs
        self.showSearchPill = showSearchPill
        self.onCmdK = onCmdK
        self.trailing = trailing
    }

    public var body: some View {
        // Linear top bar: a flat `Background.panel` chrome strip with a single
        // 1px `Line.hairline` bottom rim — no glass, no capsule. Layout of
        // crumbs/search/cmdK/trailing is unchanged.
        HStack(spacing: 14) {
            breadcrumbs

            Spacer(minLength: 12)

            if showSearchPill {
                searchPill
            }

            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(NexusColor.Background.panel)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(height: 1)
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(NexusColor.Text.muted)
                }

                // The active (last) crumb is the page title — Porcelain ink,
                // h3 weight; ancestors recede to Storm Cloud body.
                Text(crumb)
                    .font(index == crumbs.count - 1 ? NexusType.h3 : NexusType.body)
                    .foregroundStyle(index == crumbs.count - 1 ? NexusColor.Text.primary : NexusColor.Text.secondary)
            }
        }
    }

    private var searchPill: some View {
        Button(action: onCmdK) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(NexusColor.Text.tertiary)

                Text("Search or run...")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)

                Spacer(minLength: 8)

                // LabKit `LabCommandBar` ⌘K chip idiom.
                // ⌘K chip: Gunmetal (`Line.strong`) fill, mono ink, 4px radius.
                Text("⌘K")
                    .font(NexusType.mono)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        NexusColor.Line.strong,
                        in: RoundedRectangle(cornerRadius: NexusRadius.badge)
                    )
            }
            .padding(.horizontal, 12)
            .frame(height: Self.searchHeight)
            .frame(minWidth: Self.searchMinWidth)
            .background(
                NexusColor.Background.control,
                in: RoundedRectangle(cornerRadius: NexusRadius.r1)
            )
            .overlay {
                RoundedRectangle(cornerRadius: NexusRadius.r1)
                    .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .nexusTopBarKeyboardShortcut()
        .help("Search or run")
        .accessibilityLabel("Search or run")
    }
}

extension NexusTopBar where Trailing == EmptyView {
    public init(
        crumbs: [String],
        showSearchPill: Bool = true,
        onCmdK: @escaping () -> Void = {}
    ) {
        self.crumbs = crumbs
        self.showSearchPill = showSearchPill
        self.onCmdK = onCmdK
        self.trailing = { EmptyView() }
    }
}

extension View {
    @ViewBuilder
    fileprivate func nexusTopBarKeyboardShortcut() -> some View {
        keyboardShortcut("k", modifiers: .command)
    }
}
#endif
