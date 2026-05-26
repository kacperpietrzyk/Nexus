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
                Text("Witaj w Nexus")
                    .font(NexusType.h1)
                    .foregroundStyle(NexusColor.Text.primary)

                Text("Twoje zadania, notatki i spotkania w jednym miejscu. Lokalnie, w Twoim iCloud.")
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
                Text("Szybki capture")
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
        "Wciśnij ⌘⌃N w dowolnym momencie, żeby otworzyć okno capture i wpisać zadanie naturalnym językiem."
        #else
        "Stuknij pillkę „Capture” na dole ekranu, żeby szybko zapisać zadanie naturalnym językiem."
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
