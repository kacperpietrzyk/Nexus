import SwiftUI

// MARK: - NexusTextEditor

/// The canonical themed multi-line editor — the de-systemed replacement for a
/// raw `TextEditor`, whose opaque system background clashes with the Liquid
/// palette. A fixed-min-height scroll box on the same control-tile recipe as
/// `NexusTextField` (control fill, hairline → accent-on-focus border, r1).
///
/// Use this for note bodies, prompts, and code/markdown blocks. The `monospaced`
/// variant carries `NexusType.mono` for code/HTML/RRULE sources. For inputs that
/// grow with content (1–3 line titles) prefer `NexusTextField(axis: .vertical)`.
///
/// Usage:
/// ```swift
/// NexusTextEditor(text: $notes, minHeight: 120)
/// NexusTextEditor(text: $source, minHeight: 160, isMonospaced: true)
/// ```
public struct NexusTextEditor: View {

    @Binding private var text: String
    private let minHeight: CGFloat
    private let isMonospaced: Bool

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        minHeight: CGFloat = 120,
        isMonospaced: Bool = false
    ) {
        self._text = text
        self.minHeight = minHeight
        self.isMonospaced = isMonospaced
    }

    public var body: some View {
        TextEditor(text: $text)
            .focused($isFocused)
            .font(isMonospaced ? NexusType.mono : NexusType.body)
            .foregroundStyle(NexusColor.Text.primary)
            .tint(NexusColor.Accent.lime)
            .scrollContentBackground(.hidden)
            .padding(10)
            .frame(minHeight: minHeight)
            .background(
                NexusColor.Background.control,
                in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                    .strokeBorder(isFocused ? NexusColor.Accent.lime : NexusColor.Line.hairline, lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

#if DEBUG
#Preview {
    struct Demo: View {
        @State private var notes = "Plan the lab\nSetup the VM"
        @State private var code = "let x = 1\nprint(x)"
        var body: some View {
            VStack(spacing: 12) {
                NexusTextEditor(text: $notes, minHeight: 100)
                NexusTextEditor(text: $code, minHeight: 80, isMonospaced: true)
            }
            .padding(40)
            .frame(width: 320)
            .background(NexusColor.Background.base)
        }
    }
    return Demo()
}
#endif
