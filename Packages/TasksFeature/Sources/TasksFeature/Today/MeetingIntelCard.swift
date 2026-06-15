import NexusUI
import SwiftUI

/// `Meeting Intelligence` card (spec §Main bottom row 3): the most recent
/// processed meeting — title, ≤3-line summary excerpt, action-item count, and
/// a status badge. The data arrives as a `LiquidTodayMeetingIntel` value from
/// the app layer (TasksFeature never imports NexusMeetings).
struct MeetingIntelCard: View {

    let intel: LiquidTodayMeetingIntel?
    let onOpenMeetings: () -> Void

    var body: some View {
        TodayGlassCard("Meeting Intelligence") {
            if let intel {
                content(intel)
            } else {
                LiquidEmptyState(
                    systemImage: "person.wave.2",
                    message: "No processed meetings yet."
                ) {
                    LiquidPrimaryButton("Open Meetings", action: onOpenMeetings)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func content(_ intel: LiquidTodayMeetingIntel) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            meetingHeader(intel)

            if !intel.summary.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("Summary")
                        .font(DS.FontToken.metadata.weight(.semibold))
                        .foregroundStyle(DS.ColorToken.textSecondary)
                    // Stored summaries can carry Markdown heading chrome; the
                    // excerpt renders plain ink (LiquidTodayText strips it).
                    Text(LiquidTodayText.strippingMarkers(from: intel.summary))
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        // Spec §Meeting Intelligence: "summary text max 3 lines".
                        .lineLimit(3)
                }
                .padding(DS.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(Color.white.opacity(0.006))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .stroke(Color.white.opacity(0.050), lineWidth: 1)
                }
            }

            if !intel.decisions.isEmpty {
                decisionRows(intel.decisions)
            }

            if intel.actionItemCount > 0 {
                HStack(spacing: DS.Space.xs) {
                    // Spec §Meeting Intelligence: "action items use empty circles".
                    Image(systemName: "circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    Text(
                        intel.actionItemCount == 1
                            ? "1 action item" : "\(intel.actionItemCount) action items"
                    )
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }

            Spacer(minLength: 0)
            LiquidCardFooterLink("View full meeting", action: onOpenMeetings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func meetingHeader(_ intel: LiquidTodayMeetingIntel) -> some View {
        // Title + status pill share the top line; the date · time · duration
        // metadata sits on its own full-width line below so it is never
        // squeezed by the pill into a wrap or truncation (narrow 3-col card).
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .top, spacing: DS.Space.s) {
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.ColorToken.accentPurple)
                    .frame(width: 26, height: 26)
                    .background {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .fill(DS.ColorToken.accentPurple.opacity(0.14))
                    }
                Text(intel.title)
                    .font(DS.FontToken.bodyStrong)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: DS.Space.xs)
                LiquidPill(intel.statusLabel, color: DS.ColorToken.accentGreen)
            }

            Text(Self.metadataLine(for: intel))
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(DS.Space.m)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(Color.white.opacity(0.008))
                .overlay {
                    LinearGradient(
                        colors: [DS.ColorToken.accentPurple.opacity(0.052), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .stroke(Color.white.opacity(0.052), lineWidth: 1)
        }
    }

    /// Up to three parsed decisions as green-check rows
    /// (spec §Meeting Intelligence: "decisions use checkmarks").
    private func decisionRows(_ decisions: [String]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(Array(decisions.prefix(3).enumerated()), id: \.offset) { _, decision in
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.accentGreen)
                    Text(decision)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    static func metadataLine(for intel: LiquidTodayMeetingIntel) -> String {
        var parts = [dayFormatter.string(from: intel.occurredAt)]
        if intel.durationSec > 0 {
            parts.append("\(max(1, intel.durationSec / 60)) min")
        }
        return parts.joined(separator: " · ")
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEE, MMM d · h:mm a"
        return formatter
    }()
}
