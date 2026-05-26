import NexusCore
import SwiftUI

#if !os(watchOS)

/// Read-only build/version + links. Pulls bundle version from the app's Info.plist via
/// `Bundle.main`. NexusCore version comes from the `NexusCore.version` constant.
public struct AboutSettingsSection: View {
    public init() {}

    public var body: some View {
        Section {
            LabeledContent("Nexus", value: Bundle.main.shortVersion)
            LabeledContent("Build", value: Bundle.main.bundleVersion)
            LabeledContent("Core", value: NexusCore.version)
        } header: {
            nexusSettingsSectionHeader("About")
        }
    }
}

extension Bundle {
    fileprivate var shortVersion: String {
        (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
    fileprivate var bundleVersion: String {
        (object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
}

#endif
