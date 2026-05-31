import SwiftUI

public enum NexusCardElevation: Sendable, Equatable {
    case elev1
    case elev2
}

/// Flat Linear card container.
///
/// Layered `Background.*` surface + a contained `s1` drop shadow + a 1px
/// `Line.hairline` rim — no translucent glass, no glow. `elev1` sits on the
/// graphite panel surface; `elev2` is the raised slate surface.
public struct NexusCard<Content: View>: View {

    public let elevation: NexusCardElevation
    public let padding: CGFloat
    @ViewBuilder public let content: () -> Content

    public init(
        _ elevation: NexusCardElevation = .elev1,
        padding: CGFloat = 12,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.elevation = elevation
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(surfaceFill, in: cardShape)
            .overlay(cardShape.strokeBorder(NexusColor.Line.hairline, lineWidth: 1))
            .nexusShadow(NexusShadow.s1)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
    }

    internal var surfaceFill: Color {
        switch elevation {
        case .elev1: return NexusColor.Background.panel
        case .elev2: return NexusColor.Background.raised
        }
    }
}

#Preview("Elev 1") {
    NexusCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Standard card").nexusType(.h3).foregroundStyle(NexusColor.Text.primary)
            Text("With muted body text below.").nexusType(.body).foregroundStyle(
                NexusColor.Text.tertiary)
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}

#Preview("Elev 2") {
    NexusCard(.elev2) {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hero / morning brief").nexusType(.h2).foregroundStyle(
                NexusColor.Text.primary)
            Text("Raised slate elevation").nexusType(.body).foregroundStyle(
                NexusColor.Text.tertiary)
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
