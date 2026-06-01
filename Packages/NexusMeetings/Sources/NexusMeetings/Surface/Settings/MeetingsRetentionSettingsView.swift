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
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Audio retention")
            NexusSettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    NexusSettingsRow("Default policy") {
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
                    NexusSettingsDivider()

                    NavigationLink {
                        MeetingsStorageUsageView(composition: composition)
                    } label: {
                        NexusSettingsRow("Show storage usage") {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NexusColor.Text.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
