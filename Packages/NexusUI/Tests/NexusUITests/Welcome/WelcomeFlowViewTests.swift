import SwiftUI
import Testing

@testable import NexusUI

#if !os(watchOS)

@Suite("WelcomeFlowView")
@MainActor
struct WelcomeFlowViewTests {
    /// Resolves the body with no extra screens so the glass-card wrapper
    /// (`.padding(26)` + `.nexusGlass(.regular, in: RoundedRectangle…)`)
    /// and the capsule `pageDots` resolve along the `case 0`
    /// (`WhatIsNexusScreen`) path. `flow` is a private `@State`, so
    /// per-screen advancement (and therefore the `case 1` / `default`
    /// switch arms) is not externally drivable here — the flow's
    /// per-screen advance is covered by `WelcomeFlowStateTests` /
    /// `WelcomeFlowStateMLXTests`, and the individual screens by
    /// `WelcomeScreensTests`. This guard pins only the slice-1
    /// card-container + capsule page-dot idiom against build/resolution
    /// regressions (slice-1-of-MP-4.1 body-resolution-guard precedent).
    @Test("body resolves without extra screens")
    func bodyResolvesNoExtraScreens() {
        let view = WelcomeFlowView(onFinished: {})
        _ = view.body
    }

    /// Resolves the body with one injected extra screen. Because `flow`
    /// is a private `@State` starting at `currentScreen == 0`, the body
    /// still resolves the `case 0` (`WhatIsNexusScreen`) arm — the
    /// `extraScreens`/`default` arm is NOT body-resolvable from here. The
    /// extra screen still exercises the slice-1 deliverable: `pageDots`'
    /// `ForEach(0..<flow.totalScreenCount)` grows with the injected
    /// screen, so this guards the capsule-dot count against the extended
    /// flow alongside the glass-card wrap.
    @Test("body resolves with one extra screen")
    func bodyResolvesWithExtraScreen() {
        let view = WelcomeFlowView(
            onFinished: {},
            extraScreens: [{ _ in AnyView(Color.clear) }]
        )
        _ = view.body
    }
}

#endif
