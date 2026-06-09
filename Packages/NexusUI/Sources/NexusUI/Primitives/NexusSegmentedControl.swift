#if !os(watchOS)
import SwiftUI

public struct NexusSegmentedItem<ID: Hashable>: Identifiable, @unchecked Sendable {
    public let id: ID
    public let label: String
    public let systemImage: String?

    public init(id: ID, label: String, systemImage: String? = nil) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
    }
}

/// Themed Linear segmented control — the de-glassed replacement for the stock
/// `.segmented` `Picker`, whose grey-blue chrome reads alien against the
/// Midnight Command Center palette.
///
/// The track is a recessed `Background.control` substrate with a hairline rim;
/// the active segment carries a Neon Lime fill with `limeInk` text — the same
/// sanctioned `.primary` lime treatment as `NexusButton(.primary)` and the
/// "Plan my day" pill. Inactive segments are neutral `Text.tertiary` ink. Lime
/// here marks the single active selection, never decorative chrome.
public struct NexusSegmentedControl<ID: Hashable>: View {
    internal static var segmentHeight: CGFloat { 26 }

    public let items: [NexusSegmentedItem<ID>]
    @Binding public var selection: ID

    public init(items: [NexusSegmentedItem<ID>], selection: Binding<ID>) {
        self.items = items
        self._selection = selection
    }

    /// Whether the given item id is the active selection. Exposed for tests +
    /// to keep the fill/ink decision in one place.
    internal func isSelected(_ id: ID) -> Bool { id == selection }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                Button {
                    selection = item.id
                } label: {
                    segmentLabel(for: item)
                        .frame(maxWidth: .infinity)
                        .frame(height: Self.segmentHeight)
                        .foregroundStyle(
                            isSelected(item.id) ? NexusColor.Accent.limeInk : NexusColor.Text.tertiary
                        )
                        .background(
                            isSelected(item.id) ? NexusColor.Accent.lime : Color.clear,
                            in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(isSelected(item.id) ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .padding(3)
        .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        )
    }

    private func segmentLabel(for item: NexusSegmentedItem<ID>) -> some View {
        HStack(spacing: 5) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12))
            }
            Text(item.label)
                .font(NexusType.bodySmall.weight(.semibold))
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var scope = "week"
        var body: some View {
            NexusSegmentedControl(
                items: [
                    .init(id: "day", label: "Day"),
                    .init(id: "week", label: "Week"),
                    .init(id: "month", label: "Month"),
                ],
                selection: $scope
            )
            .frame(maxWidth: 240)
            .padding(40)
            .background(NexusColor.Background.base)
        }
    }
    return Demo()
}
#endif
