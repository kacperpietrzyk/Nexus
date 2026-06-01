import SwiftUI

/// Flat Linear settings card — the reusable promotion of the Mac Settings
/// `macSettingsCard`/`macSettingsRow`/`macDivider` idiom.
///
/// Depth comes from a contained `s2` drop shadow over a FULL-alpha
/// `Background.raised` fill (the unified elevation decision — no translucent
/// surface, no diffuse glow). A 1px `Line.hairline` rim closes the edge. Rows
/// and dividers below compose inside the card.
public struct NexusSettingsCard<Content: View>: View {

    @ViewBuilder public let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusColor.Background.raised, in: cardShape)
            .overlay(cardShape.strokeBorder(NexusColor.Line.hairline, lineWidth: 1))
            .nexusShadow(NexusShadow.s2)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
    }
}

/// Eyebrow section header matching the Mac Settings idiom — Inter-SemiBold
/// 10 / uppercase / `Text.muted`. The public counterpart of the internal
/// `nexusSettingsSectionHeader` free function (distinct symbol to avoid an
/// in-module redeclaration).
@MainActor public func nexusSettingsCardSectionHeader(_ title: String) -> some View {
    Text(title)
        .nexusType(NexusType.Metrics.eyebrow)
        .foregroundStyle(NexusColor.Text.muted)
}

/// A single titled row inside a `NexusSettingsCard`. Title on the left
/// (bodySmall / medium / `Text.primary`), trailing accessory on the right,
/// separated by a flexible spacer. Min row height 44pt; horizontal padding s4.
public struct NexusSettingsRow<Accessory: View>: View {

    public let title: String
    @ViewBuilder public let accessory: () -> Accessory

    public init(
        _ title: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.accessory = accessory
    }

    public var body: some View {
        HStack(alignment: .center, spacing: NexusSpacing.s4) {
            Text(title)
                .font(NexusType.bodySmall.weight(.medium))
                .foregroundStyle(NexusColor.Text.primary)
            Spacer(minLength: NexusSpacing.s4)
            accessory()
        }
        .padding(.horizontal, NexusSpacing.s4)
        .frame(minHeight: 44)
    }
}

/// Hairline divider between rows inside a `NexusSettingsCard`. Inset to the
/// row's horizontal padding so it reads as an internal seam, not a full bleed.
public struct NexusSettingsDivider: View {

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(NexusColor.Line.hairline)
            .frame(height: 1)
            .padding(.horizontal, NexusSpacing.s4)
    }
}

#Preview("Settings card") {
    VStack(alignment: .leading, spacing: NexusSpacing.s4) {
        nexusSettingsCardSectionHeader("Sync")
        NexusSettingsCard {
            VStack(spacing: 0) {
                NexusSettingsRow("iCloud sync") {
                    Text("On")
                        .font(NexusType.bodySmall.weight(.medium))
                        .foregroundStyle(NexusColor.Text.secondary)
                }
                NexusSettingsDivider()
                NexusSettingsRow("Container") {
                    Text("iCloud.com.example.Nexus")
                        .font(NexusType.bodySmall.weight(.medium))
                        .foregroundStyle(NexusColor.Text.secondary)
                }
            }
        }
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
