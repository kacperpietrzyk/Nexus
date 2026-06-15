import SwiftUI

// MARK: - NexusSelect

/// A themed dropdown control that mirrors the `NexusDateField` control-tile idiom:
/// a button with a control-background tile that opens a list popover.
///
/// Generic over `Value: Hashable`; carries no dependency on NexusCore — all
/// option-to-string mapping is supplied by the caller via `label`.
///
/// Usage:
/// ```swift
/// NexusSelect(
///     selection: $status,
///     options: ProjectStatus.allCases,
///     label: { statusLabel($0) },
///     accessibilityLabel: "Status"
/// )
/// ```
public struct NexusSelect<Value: Hashable>: View {

    // MARK: - Public interface

    @Binding public var selection: Value
    public let options: [Value]
    public let label: (Value) -> String
    public var isEnabled: Bool = true
    public let accessibilityLabel: String

    public init(
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String,
        isEnabled: Bool = true,
        accessibilityLabel: String
    ) {
        self._selection = selection
        self.options = options
        self.label = label
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
    }

    // MARK: - Private state

    @State private var presented = false

    // MARK: - Body

    public var body: some View {
        Button {
            presented = true
        } label: {
            triggerContent
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(label(selection))
        // `popover` is unavailable on watchOS; fall back to a sheet there.
        #if os(watchOS)
        .sheet(isPresented: $presented) {
            optionList
        }
        #else
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            optionList
        }
        #endif
    }

    // MARK: - Trigger tile

    /// Control-tile button styled like `NexusDateField`: control background,
    /// hairline border, r1 radius, bodySmall text, trailing chevron.
    private var triggerContent: some View {
        HStack(spacing: 6) {
            Text(label(selection))
                .font(NexusType.bodySmall)
                .foregroundStyle(isEnabled ? NexusColor.Text.primary : NexusColor.Text.disabled)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NexusColor.Text.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            NexusColor.Background.control,
            in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        )
    }

    // MARK: - Option list popover

    /// A scrollable list (capped at ~260 pt) shown inside the popover.
    /// Each row has a hover highlight and a leading checkmark for the
    /// selected value. Selecting an option updates `selection` and dismisses.
    private var optionList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(options, id: \.self) { option in
                    OptionRow(
                        text: label(option),
                        isSelected: option == selection
                    ) {
                        selection = option
                        presented = false
                    }
                }
            }
            .padding(6)
        }
        .frame(minWidth: 160)
        .frame(maxHeight: 260)
        .background(NexusColor.Background.raised)
    }
}

// MARK: - OptionRow

/// A single row in the `NexusSelect` popover. Highlights on hover and
/// shows a leading checkmark for the currently selected option.
private struct OptionRow: View {
    let text: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 14)

                Text(text)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                    .fill(isHovered ? NexusColor.Background.controlHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        // `onHover` is unavailable on watchOS (no pointer).
        #if !os(watchOS)
        .onHover { hovering in
            isHovered = hovering
        }
        #endif
    }
}
