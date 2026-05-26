import SwiftUI

#if !os(watchOS)

/// Read-only view of CloudKit env state. Real sync state observable lands in Phase 0b's
/// `SyncState` — caller injects the bound view as `syncStateView`. 0f shows static text only.
public struct SyncSettingsSection: View {
    public let cloudKitEnabled: Bool
    public let containerIdentifier: String
    public let syncStateView: AnyView?

    public init(cloudKitEnabled: Bool, containerIdentifier: String, syncStateView: AnyView? = nil) {
        self.cloudKitEnabled = cloudKitEnabled
        self.containerIdentifier = containerIdentifier
        self.syncStateView = syncStateView
    }

    public var body: some View {
        Section {
            syncStatusCard {
                VStack(alignment: .leading, spacing: 7) {
                    #if os(macOS)
                    HStack(spacing: 9) {
                        // §3 categorical: Semantic.positive/negative → ink
                        // ladder; the `checkmark.icloud.fill`/`icloud.slash`
                        // glyph shape carries connected-vs-unavailable
                        // (oracle has no hue, "✓ zsync" is text + §2
                        // LabPalette.read). Connected = settled-good →
                        // Text.secondary; unavailable = salient →
                        // Text.primary (§2 LabPalette.ink).
                        Image(systemName: cloudKitEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(
                                cloudKitEnabled ? NexusColor.Text.tertiary : NexusColor.Text.secondary
                            )
                        Text(cloudKitEnabled ? "iCloud aktywny" : "iCloud niedostępny")
                            .font(NexusType.bodySmall.weight(.semibold))
                            .foregroundStyle(NexusColor.Text.primary)
                    }
                    Text(containerIdentifier)
                        .font(NexusType.mono)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(cloudKitEnabled ? "Prywatna baza CloudKit jest włączona." : "Wyłączone w lokalnym środowisku deweloperskim.")
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                    #else
                    LabeledContent("CloudKit") {
                        Text(cloudKitEnabled ? "Włączony" : "Wyłączony (dev)")
                            .foregroundStyle(cloudKitEnabled ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    }
                    LabeledContent("Kontener") {
                        Text(containerIdentifier)
                            .font(NexusType.mono)
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    #endif
                }
            }
            if let syncStateView { syncStateView }
        } header: {
            nexusSettingsSectionHeader("Synchronizacja")
        }
    }

    private func syncStatusCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .fill(NexusColor.Background.raised.opacity(0.58))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

#endif
