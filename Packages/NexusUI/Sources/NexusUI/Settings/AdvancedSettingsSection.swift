import SwiftUI

#if !os(watchOS)

/// "Export to Folder…" + future power-user surfaces.
/// The export action delegates to a caller-provided closure so Settings doesn't
/// take a hard dependency on `MarkdownExporter`.
public struct AdvancedSettingsSection: View {
    public let onExportRequested: () -> Void

    public init(onExportRequested: @escaping () -> Void) {
        self.onExportRequested = onExportRequested
    }

    public var body: some View {
        Section {
            Button("Export to Folder…", action: onExportRequested)
        } header: {
            nexusSettingsSectionHeader("Advanced")
        }
    }
}

#endif
