import NexusCore
import SwiftUI

public struct MeetingsRetentionSettingsView: View {
    private let composition: MeetingsComposition
    @AppStorage(MeetingsSettingsKeys.retentionPolicy, store: .nexusGroup) private var rawPolicy = "30d"

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        Section("Audio retention") {
            Picker("Default policy", selection: $rawPolicy) {
                Text("7 days").tag("7d")
                Text("30 days").tag("30d")
                Text("Forever").tag("forever")
                Text("Never save").tag("never")
            }

            NavigationLink("Show storage usage") {
                MeetingsStorageUsageView(composition: composition)
            }
        }
    }
}
