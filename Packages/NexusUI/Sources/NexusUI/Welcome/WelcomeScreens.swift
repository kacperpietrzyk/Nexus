import SwiftUI

#if !os(watchOS)

public struct WhatIsNexusScreen: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            // §3 achromatic: screen-identity glyphs are NOT Emphasis. Oracle LabPalette.read → Text.secondary
            // (§2 1:1 map). Single Text.primary emphasis reserved for h1 title (§3 single-emphasis lock).
            // Salience carried by 64pt size, not hue. Applies to both hero icons in this file.
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(NexusColor.Text.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Welcome to Nexus")
                    .font(NexusType.h1)
                    .foregroundStyle(NexusColor.Text.primary)

                Text("Your tasks, notes, and meetings in one place. Local, in your iCloud.")
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

public struct CaptureFlowScreen: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 40)

            Image(systemName: "command.square.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(NexusColor.Text.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Quick capture")
                    .font(NexusType.h1)
                    .foregroundStyle(NexusColor.Text.primary)

                Text(copy)
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)

                shortcutPreview
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private var copy: String {
        #if os(macOS)
        "Press \u{2318}\u{2303}N at any time to open the capture window and type a task in natural language."
        #else
        "Tap the \"Capture\" pill at the bottom of the screen to quickly save a task in natural language."
        #endif
    }

    @ViewBuilder
    private var shortcutPreview: some View {
        #if os(macOS)
        NexusKbd.combo(["⌘", "⌃", "N"])
        #else
        EmptyView()
        #endif
    }
}

#endif
