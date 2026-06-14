import NexusCore
import NexusUI
import SwiftUI

public struct MeetingsRetentionSettingsView: View {
    private let composition: MeetingsComposition
    @AppStorage(MeetingsSettingsKeys.retentionPolicy, store: .nexusGroup) private var rawPolicy = "30d"

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        LiquidGlassCard("Audio retention") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Default policy")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Picker("Default policy", selection: $rawPolicy) {
                        Text("7 days").tag("7d")
                        Text("30 days").tag("30d")
                        Text("Forever").tag("forever")
                        Text("Never save").tag("never")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160, alignment: .trailing)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                NavigationLink {
                    MeetingsStorageUsageView(composition: composition)
                } label: {
                    HStack {
                        Text("Show storage usage")
                            .font(DS.FontToken.body)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.textMuted)
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
