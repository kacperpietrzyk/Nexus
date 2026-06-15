import SwiftUI

/// Consent band offering the one-time model update for existing users (no welcome
/// flow). Wi-Fi-gated: on cellular the primary action defers to "Download anyway".
///
/// Presentation-only — callers supply `onDownload` / `onLater`; no business logic
/// lives here. Wire this into an assistant surface in a later task.
public struct AssistantUpdateBand: View {
    private let modelName: String
    private let sizeGB: Double
    private let onDownload: () -> Void
    private let onLater: () -> Void
    @State private var reachability = WiFiReachability()

    public init(
        modelName: String,
        sizeGB: Double,
        onDownload: @escaping () -> Void,
        onLater: @escaping () -> Void
    ) {
        self.modelName = modelName
        self.sizeGB = sizeGB
        self.onDownload = onDownload
        self.onLater = onLater
    }

    public var body: some View {
        LiquidGlassCard {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Label {
                    Text("Assistant needs an update")
                        .font(DS.FontToken.title)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .foregroundStyle(DS.ColorToken.statusWarning)
                }

                Text("\(modelName) · \(String(format: "%.1f", sizeGB)) GB")
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)

                HStack(spacing: DS.Space.s) {
                    LiquidPrimaryButton(
                        reachability.isOnWiFi ? "Download on Wi-Fi" : "Download anyway",
                        systemImage: reachability.isOnWiFi ? "wifi" : "arrow.down.circle",
                        action: onDownload
                    )

                    Button("Later", action: onLater)
                        .font(DS.FontToken.button)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .buttonStyle(LiquidPressButtonStyle())
                }

                if !reachability.isOnWiFi {
                    Text("Connect to Wi-Fi to avoid cellular data.")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
            }
        }
    }
}
