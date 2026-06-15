import SwiftUI

// MARK: - NexusTextField

/// The canonical themed text input — the de-systemed replacement for a raw
/// `TextField`, whose `.roundedBorder`/`.plain` chrome and blue focus ring clash
/// with the Liquid palette.
///
/// Shares the exact control-tile idiom as `NexusSelect` / `NexusDateField`:
/// `Background.control` fill, hairline border, `r1` radius, `bodySmall` text. On
/// focus the hairline swaps for a 1px Liquid-accent ring (replacing the native
/// blue one). Supports the size, axis, monospace and leading-icon (search)
/// variants observed across the app so every input is designed once here.
///
/// Usage:
/// ```swift
/// NexusTextField("New tag", text: $draft)                       // standard
/// NexusTextField("Search", text: $query, leadingSystemImage: "magnifyingglass")
/// NexusTextField("Notes", text: $body, axis: .vertical, lineLimit: 1...3)
/// NexusTextField("Cron", text: $cron, isMonospaced: true, size: .compact)
/// ```
public struct NexusTextField: View {

    /// Vertical density. `.standard` (~36pt) is the default tile; `.compact`
    /// (~30pt) matches dense rows (custom fields, key dates).
    public enum Size {
        case standard
        case compact

        var verticalPadding: CGFloat {
            switch self {
            case .standard: return 9
            case .compact: return 6
            }
        }
    }

    @Binding private var text: String
    private let placeholder: String
    private let axis: Axis
    private let lineLimit: ClosedRange<Int>?
    private let isMonospaced: Bool
    private let leadingSystemImage: String?
    private let size: Size
    private let isEnabled: Bool

    @FocusState private var isFocused: Bool

    public init(
        _ placeholder: String,
        text: Binding<String>,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int>? = nil,
        isMonospaced: Bool = false,
        leadingSystemImage: String? = nil,
        size: Size = .standard,
        isEnabled: Bool = true
    ) {
        self.placeholder = placeholder
        self._text = text
        self.axis = axis
        self.lineLimit = lineLimit
        self.isMonospaced = isMonospaced
        self.leadingSystemImage = leadingSystemImage
        self.size = size
        self.isEnabled = isEnabled
    }

    public var body: some View {
        HStack(spacing: 7) {
            if let leadingSystemImage {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            field
        }
        .padding(.horizontal, 10)
        .padding(.vertical, size.verticalPadding)
        .background(
            NexusColor.Background.control,
            in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }

    @ViewBuilder
    private var field: some View {
        let base = TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .disabled(!isEnabled)
            .foregroundStyle(isEnabled ? NexusColor.Text.primary : NexusColor.Text.disabled)
            .tint(NexusColor.Accent.lime)

        if let lineLimit {
            base.lineLimit(lineLimit).font(font)
        } else {
            base.font(font)
        }
    }

    private var font: Font {
        isMonospaced ? NexusType.mono : NexusType.bodySmall
    }

    // Focus swaps the hairline for the Liquid accent ring — the single themed
    // replacement for the native blue focus ring across the whole app.
    private var borderColor: Color {
        isFocused ? NexusColor.Accent.lime : NexusColor.Line.hairline
    }
}

#if DEBUG
#Preview {
    struct Demo: View {
        @State private var tag = ""
        @State private var search = "malware"
        @State private var notes = "Multi-line\ngrows with content"
        var body: some View {
            VStack(spacing: 12) {
                NexusTextField("New tag", text: $tag)
                NexusTextField("Search", text: $search, leadingSystemImage: "magnifyingglass")
                NexusTextField("Notes", text: $notes, axis: .vertical, lineLimit: 1...3)
                NexusTextField("Cron", text: .constant("0 9 * * 1"), isMonospaced: true, size: .compact)
            }
            .padding(40)
            .frame(width: 320)
            .background(NexusColor.Background.base)
        }
    }
    return Demo()
}
#endif
