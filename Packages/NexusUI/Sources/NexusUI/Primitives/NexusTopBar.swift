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
        // Linear top bar: the flat `NexusBarStrip` chrome idiom inlined —
        // a `Background.panel` strip with a single 1px `Line.hairline` bottom
        // rim and a contained `NexusShadow.s1`, no glass, no capsule. The
        // 18/11 padding and s1 shadow match `NexusBarStrip` exactly so this
        // top bar is visually identical chrome to the control-mode bar and
        // the bottom command bar. Layout of crumbs/search/cmdK/trailing is
        // unchanged.
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
        .nexusShadow(NexusShadow.s1)
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

                // ⌘K chip — the shared topbar/command-bar idiom:
                // `Background.control` fill + `NexusType.metaMono` ink + a
                // `Line.regular` hairline, flat r1 corners (identical to
                // `NexusCommandBar`'s chip). The border is what reads the
                // chip against the same-toned `Background.control` search
                // field it nests inside.
                Text("⌘K")
                    .font(NexusType.metaMono)
                    .foregroundStyle(NexusColor.Text.disabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: NexusRadius.r1)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r1)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }
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
