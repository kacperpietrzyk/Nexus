import NexusUI
import SwiftUI

private let shellOuterHorizontalPadding: CGFloat = DS.Space.m
private let shellOuterVerticalPadding: CGFloat = 12

/// The Liquid app frame (design-system `docs/03_COMPONENTS.md` §AppShell +
/// `docs/04_LAYOUT_SYSTEM.md` §Base shell): a translucent desktop backdrop,
/// a floating sidebar, and one command-center content shell. When a page has
/// an inspector, it is integrated inside that same shell behind an internal
/// divider instead of becoming a third floating window.
///
/// Pure layout — no business logic, no data. The host (`ContentView`)
/// composes real sidebar/toolbar/page content into the slots.
struct LiquidAppShell<Sidebar: View, Toolbar: View, Main: View, Inspector: View>: View {
    let sidebar: () -> Sidebar
    let toolbar: () -> Toolbar
    let main: () -> Main
    /// `nil` → the right-inspector column is not rendered (the content shell
    /// stretches to the trailing window edge).
    let inspector: (() -> Inspector)?

    init(
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder toolbar: @escaping () -> Toolbar,
        @ViewBuilder main: @escaping () -> Main,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        self.sidebar = sidebar
        self.toolbar = toolbar
        self.main = main
        self.inspector = inspector
    }

    /// Per-destination inspector mount: the host passes `nil` on destinations
    /// without a right column (the column disappears entirely) and a closure
    /// on those with one (e.g. Today). Distinct from the `@ViewBuilder`
    /// initializer above, which always renders the column.
    init(
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder toolbar: @escaping () -> Toolbar,
        @ViewBuilder main: @escaping () -> Main,
        inspector: (() -> Inspector)?
    ) {
        self.sidebar = sidebar
        self.toolbar = toolbar
        self.main = main
        self.inspector = inspector
    }

    var body: some View {
        ZStack {
            // Shared liquid ground (app background + wallpaper gradient) under
            // the glass panels — the same layer the Settings window paints.
            LiquidWallpaper()

            HStack(spacing: DS.Space.m) {
                sidebar()
                    .frame(width: DS.Size.sidebarWidth)

                // Layout-only — no fill / border / rounding. The cards,
                // sidebar and inspector are the only visible surfaces on the
                // backdrop (matches the reference); wrapping them in a bordered
                // glass "shell" read as an app-inside-an-app.
                contentShell
            }
            .padding(.horizontal, shellOuterHorizontalPadding)
            .padding(.vertical, shellOuterVerticalPadding)
        }
        // 04_LAYOUT_SYSTEM.md: minimum useful size 1180 × 760.
        .frame(minWidth: DS.Size.windowMinWidth, minHeight: 760)
    }

    private var contentShell: some View {
        VStack(spacing: 0) {
            toolbar()
                .frame(height: DS.Size.toolbarHeight)

            HStack(spacing: 0) {
                main()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let inspector {
                    // No drawn divider — the gap + the inspector cards' own
                    // edges separate the columns (the shell border that used to
                    // sit beside this line is gone).
                    Spacer().frame(width: DS.Space.m)

                    inspector()
                        .frame(width: DS.Size.rightInspectorWidth)
                        .frame(maxHeight: .infinity)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }
}

extension LiquidAppShell where Inspector == EmptyView {
    /// Inspector-less mount — the common case today (the task detail stays a
    /// centered modal overlay, not an inspector column).
    init(
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder toolbar: @escaping () -> Toolbar,
        @ViewBuilder main: @escaping () -> Main
    ) {
        self.sidebar = sidebar
        self.toolbar = toolbar
        self.main = main
        self.inspector = nil
    }
}
