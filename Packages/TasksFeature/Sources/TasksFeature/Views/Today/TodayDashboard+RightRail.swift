import NexusUI
import SwiftUI

extension TodayDashboard {
    func rightRailContent(digestText: String, digestTimestamp: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            captureSection
            digestCard(digestText: digestText, digestTimestamp: digestTimestamp)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.tertiary)

                Text("CAPTURE")
                    .font(NexusType.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            VStack(spacing: 6) {
                CapturePill(systemImage: "checkmark.square", label: "New task", kbdHint: "T") {
                    onOpenCapture(.task)
                }
                CapturePill(systemImage: "mic", label: "Voice memo", kbdHint: "V") {
                    onOpenCapture(.voiceMemo)
                }
            }
        }
    }

    private func digestCard(digestText: String, digestTimestamp: String) -> some View {
        NexusCard(.elev1, padding: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NexusColor.Text.tertiary)

                    Text("MORNING DIGEST")
                        .font(NexusType.eyebrow)
                        .foregroundStyle(NexusColor.Text.tertiary)

                    Spacer(minLength: 8)

                    Text(digestTimestamp)
                        .font(NexusType.mono)
                        .foregroundStyle(NexusColor.Text.muted)
                }

                DigestRenderer.render(digestText.isEmpty ? "Loading..." : digestText)
                    .font(NexusType.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    NexusBadge("+2 actions", tone: .acc)
                    NexusBadge("view source", tone: .muted)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}
