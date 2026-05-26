import SwiftUI

#if os(iOS)

public struct ExternalAccessInfoSection: View {
    public init() {}

    public var body: some View {
        Section {
            Text("MCP server is available on macOS only. To enable external agent access, open Nexus on your Mac.")
                .font(.footnote)
                .foregroundStyle(NexusColor.Text.secondary)
        } header: {
            nexusSettingsSectionHeader("External Access")
        }
    }
}

#endif
