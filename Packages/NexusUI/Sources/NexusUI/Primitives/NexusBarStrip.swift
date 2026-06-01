import SwiftUI

/// Flat Linear chrome-bar strip — the shared idiom behind top bars and the
/// bottom command bar.
///
/// A rectangular `Background.panel` strip with a single 1px `Line.hairline`
/// rim on the anchoring `edge` (bottom for a top bar, top for a bottom bar)
/// and a contained `s1` drop shadow. No corner rounding, no capsule, no glass.
/// Content gets sensible default padding (matching `NexusTopBar`'s 18 / 11)
/// but may override it from the caller.
public struct NexusBarStrip<Content: View>: View {

    public let edge: Edge
    @ViewBuilder public let content: () -> Content

    public init(
        edge: Edge = .bottom,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.edge = edge
        self.content = content
    }

    public var body: some View {
        content()
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(NexusColor.Background.panel)
            .overlay(alignment: borderAlignment) {
                Rectangle()
                    .fill(NexusColor.Line.hairline)
                    .frame(
                        width: isHorizontalEdge ? nil : 1,
                        height: isHorizontalEdge ? 1 : nil
                    )
            }
            .nexusShadow(NexusShadow.s1)
    }

    private var borderAlignment: Alignment {
        switch edge {
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        }
    }

    private var isHorizontalEdge: Bool {
        edge == .top || edge == .bottom
    }
}

#Preview("Bar strip") {
    VStack(spacing: 0) {
        NexusBarStrip(edge: .bottom) {
            HStack {
                Text("Tasks")
                    .font(NexusType.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                Spacer()
            }
        }
        Spacer()
        NexusBarStrip(edge: .top) {
            HStack {
                Text("3 selected")
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Text.tertiary)
                Spacer()
            }
        }
    }
    .frame(height: 240)
    .background(NexusColor.Background.base)
}
