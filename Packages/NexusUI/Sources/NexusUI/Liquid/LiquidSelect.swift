import SwiftUI

/// A single option in a ``LiquidSelect`` dropdown.
public struct LiquidSelectOption<ID: Hashable>: Identifiable, @unchecked Sendable {
    public let id: ID
    public let label: String
    public let systemImage: String?

    public init(id: ID, label: String, systemImage: String? = nil) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
    }
}

/// Achromatic glass dropdown per `docs/03_COMPONENTS.md` §Select — the Liquid
/// counterpart to the legacy `NexusSelect`.
///
/// A glass field (`glassSoft` fill, `strokeHairline` rim, `DS.Radius.s` corner)
/// shows the selected label plus a trailing `chevron.down`. The option list is
/// a native SwiftUI `Menu` for reliable keyboard accessibility. Achromatic by
/// design — no accent fill on the field.
public struct LiquidSelect<ID: Hashable>: View {

    public let options: [LiquidSelectOption<ID>]
    @Binding public var selection: ID
    public let placeholder: String

    public init(_ options: [LiquidSelectOption<ID>], selection: Binding<ID>, placeholder: String = "") {
        self.options = options
        self._selection = selection
        self.placeholder = placeholder
    }

    /// The currently selected option, if its id resolves to a known option.
    internal var selectedOption: LiquidSelectOption<ID>? {
        options.first { $0.id == selection }
    }

    private var displayLabel: String {
        selectedOption?.label ?? placeholder
    }

    public var body: some View {
        core
            .accessibilityValue(displayLabel)
    }

    // `Menu` is unavailable on watchOS, so that platform falls back to a native
    // `Picker` (the glass field as its label). macOS/iOS use the glass Menu.
    #if os(watchOS)
    private var core: some View {
        Picker(selection: $selection) {
            ForEach(options) { option in
                optionLabel(option).tag(option.id)
            }
        } label: {
            field
        }
    }
    #else
    private var core: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option.id
                } label: {
                    optionLabel(option)
                }
            }
        } label: {
            field
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        #elseif os(iOS)
        .menuIndicator(.hidden)
        #endif
    }
    #endif

    @ViewBuilder
    private func optionLabel(_ option: LiquidSelectOption<ID>) -> some View {
        if let systemImage = option.systemImage {
            Label(option.label, systemImage: systemImage)
        } else {
            Text(option.label)
        }
    }

    private var field: some View {
        HStack(spacing: DS.Space.xs) {
            Text(displayLabel)
                .font(DS.FontToken.body)
                .foregroundStyle(
                    selectedOption == nil ? DS.ColorToken.textTertiary : DS.ColorToken.textPrimary
                )
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textTertiary)
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(DS.ColorToken.glassSoft)
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
    }
}
