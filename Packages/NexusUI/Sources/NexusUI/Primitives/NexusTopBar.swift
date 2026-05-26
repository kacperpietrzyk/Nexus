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
        // LabKit `LabTopBar`: a glass capsule pill (no fixed height, no
        // bottom hairline — the glass rim is the edge). Layout of
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
        .nexusGlass(.regular, in: Capsule())
    }

    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(NexusColor.Text.muted)
                }

                Text(crumb)
                    .font(index == crumbs.count - 1 ? NexusType.body.weight(.semibold) : NexusType.body)
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

                Text("Szukaj lub uruchom...")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)

                Spacer(minLength: 8)

                // LabKit `LabCommandBar` ⌘K chip idiom.
                Text("⌘K")
                    .font(NexusType.mono)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .padding(.horizontal, 12)
            .frame(height: Self.searchHeight)
            .frame(minWidth: Self.searchMinWidth)
            .background(Color.white.opacity(0.065), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .nexusTopBarKeyboardShortcut()
        .help("Szukaj lub uruchom")
        .accessibilityLabel("Szukaj lub uruchom")
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
