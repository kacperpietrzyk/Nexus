import SwiftUI

/// The Liquid wallpaper layer: the DS app background plus the subtle
/// wallpaper-like accent gradient that sits UNDER the glass panels (per the
/// design-system shell scaffold, LiquidAppShellExample.swift). Shared by the
/// main app shell and the Settings window so every Liquid window paints the
/// same ground. Both layers ignore the safe area; pure decoration — no layout,
/// no business logic.
public struct LiquidWallpaper: View {

    public init() {}

    public var body: some View {
        ZStack {
            DS.ColorToken.backgroundApp
                .ignoresSafeArea()

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
        }
    }
}
