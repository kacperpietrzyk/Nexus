import NexusUI
import SwiftUI

/// `Decisions` card (Today bottom row): the ≤5 most-recent decisions parsed
/// from processed meetings, newest-first. The data arrives as
/// `[LiquidTodayDecision]` from the app layer — TasksFeature never imports
/// NexusMeetings.
struct TodayMeetingDecisionsCard: View {

    let decisions: [LiquidTodayDecision]
    let onOpenMeetings: () -> Void

    var body: some View {
        TodayGlassCard("Decisions") {
            if decisions.isEmpty {
                LiquidEmptyState(
                    systemImage: "checkmark.seal",
                    message: "No recent decisions captured."
                ) {
                    LiquidPrimaryButton("Open Meetings", action: onOpenMeetings)
                }
                .frame(maxHeight: .infinity)
            } else {
                decisionRows
            }
        }
    }

    private var decisionRows: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            ForEach(decisions) { decision in
                Button {
                    onOpenMeetings()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.ColorToken.accentGreen)
                            .frame(width: 18, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(decision.text)
                                .font(DS.FontToken.body)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(attribution(for: decision))
                                .font(DS.FontToken.metadata)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, DS.Space.xs)
                }
                .buttonStyle(.plain)

                if decision.id != decisions.last?.id {
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                }
            }
            Spacer(minLength: 0)
            LiquidCardFooterLink("View all meetings", action: onOpenMeetings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func attribution(for decision: LiquidTodayDecision) -> String {
        "\(decision.meetingTitle) · \(Self.relativeFormatter.localizedString(for: decision.meetingDate, relativeTo: .now))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()
}
