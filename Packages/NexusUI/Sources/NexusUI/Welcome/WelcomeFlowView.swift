import SwiftUI

#if !os(watchOS)

/// First-launch welcome flow. Host decides presentation and persists `welcomeShown`.
public struct WelcomeFlowView: View {
    @State private var flow: WelcomeFlowState

    private let extraScreens: [(@escaping () -> Void) -> AnyView]
    private let onFinished: () -> Void

    public init(
        onFinished: @escaping () -> Void,
        extraScreens: [(@escaping () -> Void) -> AnyView] = []
    ) {
        _flow = State(initialValue: WelcomeFlowState(extraScreenCount: extraScreens.count))
        self.extraScreens = extraScreens
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            NexusWallpaper()
                .ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            NexusButton(variant: .outline, size: .sm, action: skip) {
                Text("Skip")
            }
            .padding(20)
        }
        .onChange(of: flow.isFinished) { _, isFinished in
            if isFinished {
                handleFinished()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            // MP-4.2 §1 platform branch — glass-card geometry is applied on macOS only.
            //
            // macOS branch:
            //   Oracle `Lab/WelcomePreview.swift card(_:)` wraps each screen in
            //   `content().frame(width:320,height:380).padding(26).labGlass(
            //   RoundedRectangle(cornerRadius:20))`. The storyboard's 3-up side-by-
            //   side + chevron arrows + `ONBOARDING · 3 EKRANY` eyebrow are a Lab
            //   presentation device, NOT runtime — at first launch there is ONE card
            //   centred in the sheet (same precedent class as FlowsPreview's
            //   `FlowFrame`). Width: 360 content / 412 outer (after `.padding(26)`,
            //   mirroring the oracle's content→pad→glass order). Sized against the
            //   real Mac sheet host `WelcomeFlowView(...).frame(minWidth: 640, …)`
            //   (see `Apps/NexusMac/NexusMacApp.swift`) — macOS sheets render at the
            //   minimum, so at 640 the centred card's right edge is at x≈526. The
            //   "Skip" button is `ZStack(.topTrailing)` + `.padding(20)` over
            //   `NexusButton(.outline, .sm)` (`hPadding` 10×2 + `NexusType.meta`
            //   6-char label) ⇒ its left edge sits at x≈550 (button width ≈70,
            //   right inset 20), leaving ~24pt clearance so the card never collides
            //   with the skip affordance. Widened from the oracle's 320-content
            //   (which crushes the screens' 64pt hero icon + `NexusType.h1` title +
            //   their own `.padding(.horizontal, 32)`) up to the largest width that
            //   still clears "Skip" at minWidth 640. No fixed height: the built-in
            //   screens' `Spacer(minLength:40)…Spacer()` expand to fill the proposed
            //   sheet height through the layout-transparent `nexusGlass` (card ≈
            //   fills flexible height, expands via the screens' internal Spacers,
            //   does not hug content); the injected variable-height MLX
            //   `DownloadModelStep` differs — runtime height reconciliation
            //   deferred to slice-2/acceptance. `nexusGlass` is the MP-1-frozen
            //   reconciliation of `labGlass`.
            //
            // iOS branch (byte-identical to pre-slice-1 fluid layout):
            //   `Apps/NexusiOS/NexusiOSApp.swift` mounts `WelcomeFlowView` via
            //   `WelcomeFlowPresenter` in a `.fullScreenCover`. iPhone logical width
            //   is ~390pt (SE: 375pt). A centred glass card wide enough to be usable
            //   (~360 content + 2×26 padding = ~412pt outer) overflows the screen,
            //   and a narrower card that fits collides with the top-trailing "Skip"
            //   affordance at `.padding(20)`. Relocating "Skip" on iPhone is a
            //   structural design decision with no oracle answer (the oracle storyboard
            //   is a Mac 3-up canvas, not a runtime iPhone layout) and no user was
            //   available under the autonomous mandate to choose. Therefore the iOS
            //   Welcome oracle-card geometry is **deferred to MP-5.1** (requires
            //   "Skip" placement decision + iPhone hardware smoke) — same precedent
            //   class as MP-4.1's iOS Settings deferral. The #else arm is the
            //   byte-identical pre-slice-1 fluid layout.
            #if os(macOS)
            currentScreen
                .frame(width: 360)
                .padding(26)
                .nexusGlass(.regular, in: RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            currentScreen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif

            VStack(spacing: 16) {
                pageDots
                if !isShowingExtraScreen {
                    primaryButton
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch flow.currentScreen {
        case 0:
            WhatIsNexusScreen()
        case 1:
            CaptureFlowScreen()
        default:
            let extraIndex = flow.currentScreen - WelcomeFlowState.totalScreens
            if extraScreens.indices.contains(extraIndex) {
                extraScreens[extraIndex](advance)
            } else {
                CaptureFlowScreen()
            }
        }
    }

    private var pageDots: some View {
        // MP-4.2 §1: oracle `Lab/WelcomePreview.swift card(_:)`
        // page-dots — `Capsule().fill(i == step ? ink : dim).frame(
        // width: i == step ? 16 : 5, height: 5)` in `HStack(spacing:6)`.
        // Shape (Circle→Capsule) + active-dimension change, NOT an accent
        // burn — the dots were already achromatic. §2 1:1 hex map:
        // `LabPalette.ink (0xF2F2F4) → Text.primary`, `LabPalette.dim
        // (0x44454E) → Text.disabled`.
        HStack(spacing: 6) {
            ForEach(0..<flow.totalScreenCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index == flow.currentScreen
                            ? NexusColor.Text.primary
                            : NexusColor.Text.disabled
                    )
                    .frame(width: index == flow.currentScreen ? 16 : 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(flow.currentScreen + 1) of \(flow.totalScreenCount)")
    }

    private var primaryButton: some View {
        NexusButton(variant: .primary, size: .lg, action: advance) {
            Text(flow.isLastScreen ? "Let's go" : "Next")
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: 320)
    }

    private func advance() {
        flow.advance()
    }

    private func skip() {
        flow.skip()
    }

    private var isShowingExtraScreen: Bool {
        // Every extra screen (index >= the 2 built-ins) owns its own continue
        // affordance — the shared primary button is suppressed for all of them,
        // not just the last.
        !extraScreens.isEmpty && flow.currentScreen >= WelcomeFlowState.totalScreens
    }

    @MainActor
    private func handleFinished() {
        Task {
            await PermissionRequester.requestAll()
        }
        onFinished()
    }
}

#endif
