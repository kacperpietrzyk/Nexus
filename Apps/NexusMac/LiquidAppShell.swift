import NexusUI
import SwiftUI

/// The Liquid app frame (design-system `docs/03_COMPONENTS.md` §AppShell +
/// `docs/04_LAYOUT_SYSTEM.md` §Base shell): a deep dark background with a
/// subtle wallpaper gradient under glass, then three floating glass columns —
/// the 224 pt sidebar, the flexible content shell (58 pt toolbar + page
/// content), and an OPTIONAL 304 pt right inspector. The inspector slot is
/// per-destination: `nil` means the column is absent entirely (not an empty
/// glass panel).
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

    var body: some View {
        ZStack {
            DS.ColorToken.backgroundApp.ignoresSafeArea()

            // Wallpaper-like gradient under the glass panels, per the
            // design-system shell scaffold (LiquidAppShellExample.swift).
            LinearGradient(
                colors: [
                    DS.ColorToken.accentBlue.opacity(0.10),
                    DS.ColorToken.backgroundApp,
                    DS.ColorToken.accentAmber.opacity(0.08),
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .ignoresSafeArea()

            HStack(spacing: DS.Space.m) {
                sidebar()
                    .frame(width: DS.Size.sidebarWidth)

                VStack(spacing: 0) {
                    toolbar()
                        .frame(height: DS.Size.toolbarHeight)
                    main()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Clip the page content to the window radius FIRST so square
                // scroll content cannot bleed past the glass corners; the
                // glass recipe then paints background/stroke/shadow around it.
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.window, style: .continuous))
                .liquidGlass(.shell, radius: DS.Radius.window)

                if let inspector {
                    inspector()
                        .frame(width: DS.Size.rightInspectorWidth)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.window, style: .continuous))
                        .liquidGlass(.sidebar, radius: DS.Radius.window)
                }
            }
            .padding(DS.Space.m)
        }
        // 04_LAYOUT_SYSTEM.md: minimum useful size 1180 × 760.
        .frame(minWidth: DS.Size.windowMinWidth, minHeight: 760)
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
