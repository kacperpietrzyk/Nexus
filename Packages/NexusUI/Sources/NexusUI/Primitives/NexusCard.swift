import SwiftUI

public enum NexusCardElevation: Sendable, Equatable {
    case elev1
    case elev2
}

/// Card container backed by the v4 glass elevation scale.
public struct NexusCard<Content: View>: View {

    public let elevation: NexusCardElevation
    public let padding: CGFloat
    @ViewBuilder public let content: () -> Content

    public init(
        _ elevation: NexusCardElevation = .elev1,
        padding: CGFloat = 24,
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
            .nexusGlass(glassVariant, cornerRadius: NexusRadius.r3)
            .nexusGlassRim(cornerRadius: NexusRadius.r3)
            .nexusShadow(NexusShadow.glass)
    }

    internal var glassVariant: NexusGlassVariant {
        switch elevation {
        case .elev1: return .subtle
        case .elev2: return .regular
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
            Text("Regular glass elevation").nexusType(.body).foregroundStyle(
                NexusColor.Text.tertiary)
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
