#if os(macOS)
import AppKit
import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// Right inspector for the Meetings screen (spec §Right inspector), 304 pt
/// shell slot: Follow-up Tasks, Send Summary, Insights, Next Meeting. Every
/// card reads the shared `LiquidMeetingsModel`; only REAL actions ship —
/// "Send to attendees" / "Share to channel" from the mockup have no backend
/// (no mail/channel integration exists) and are intentionally omitted in
/// favor of a real clipboard copy and the system share sheet.
public struct MeetingActionsInspector: View {

    private let model: LiquidMeetingsModel
    private let composition: MeetingsComposition
    @ObservedObject private var router: MeetingNavigationRouter
    private let navigation: LiquidMeetingsNavigation

    @State private var copiedFeedback = false

    public init(
        model: LiquidMeetingsModel,
        composition: MeetingsComposition,
        router: MeetingNavigationRouter,
        navigation: LiquidMeetingsNavigation
    ) {
        self.model = model
        self.composition = composition
        self.router = router
        self.navigation = navigation
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            // 04_LAYOUT_SYSTEM.md: inspector cards stack vertically, spacing 12.
            VStack(spacing: DS.Space.m) {
                if model.meeting != nil {
                    followUpCard
                    sendSummaryCard
                    insightsCard
                }
                nextMeetingCard
                if model.knowledgeCollapsed, model.meeting != nil {
                    // Under the wide breakpoint the Knowledge Column collapses
                    // into this inspector (04_LAYOUT_SYSTEM.md §Wide desktop).
                    KnowledgeSections(
                        model: model, composition: composition, router: router,
                        navigation: navigation
                    )
                }
            }
            .padding(DS.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Follow-up Tasks

    /// Open action items of the selected meeting; the checkbox completes
    /// through the real task repository (same path as the detail card).
    @ViewBuilder
    private var followUpCard: some View {
        LiquidGlassCard("Follow-up Tasks") {
            if model.openActionItems.isEmpty {
                inspectorEmpty("No open follow-ups for this meeting.")
            } else {
                VStack(spacing: 0) {
                    ForEach(model.openActionItems, id: \.id) { task in
                        LiquidTaskRow(
                            task.title,
                            isDone: task.status == .done,
                            metadata: task.dueAt.map {
                                LiquidMeetingsFormat.dayAndTime.string(from: $0)
                            },
                            onToggle: { model.toggleActionItem(task, composition: composition) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Send Summary

    @ViewBuilder
    private var sendSummaryCard: some View {
        LiquidGlassCard("Send Summary") {
            if summaryText.isEmpty {
                inspectorEmpty("Nothing to share yet — the summary appears after processing.")
            } else {
                VStack(spacing: DS.Space.xs) {
                    actionRow(
                        systemImage: copiedFeedback ? "checkmark" : "doc.on.doc",
                        title: copiedFeedback ? "Copied" : "Copy summary"
                    ) {
                        copySummary()
                    }
                    // System share sheet over the real summary text (ShareLink
                    // presents NSSharingServicePicker on macOS).
                    ShareLink(item: summaryText) {
                        actionRowLabel(systemImage: "square.and.arrow.up", title: "Share summary…")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryText: String {
        (model.meeting?.summaryText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copySummary() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(summaryText, forType: .string)
        withAnimation(DS.Motion.selection) { copiedFeedback = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(DS.Motion.selection) { copiedFeedback = false }
        }
    }

    private func actionRow(
        systemImage: String, title: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionRowLabel(systemImage: systemImage, title: title)
        }
        .buttonStyle(.plain)
    }

    private func actionRowLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: DS.Space.s) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textSecondary)
                .frame(width: 16)
            Text(title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Insights

    /// Real aggregates from `MeetingInsights` (duration, talk share, top
    /// terms, word count). The mockup's "sentiment" has no backing analysis —
    /// omitted.
    @ViewBuilder
    private var insightsCard: some View {
        LiquidGlassCard("Insights") {
            if model.insights == .empty {
                inspectorEmpty("Insights appear once the meeting is transcribed.")
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    if let duration = model.insights.durationText {
                        insightLine(label: "Duration", value: duration)
                    }
                    if model.insights.wordCount > 0 {
                        insightLine(label: "Words", value: "\(model.insights.wordCount)")
                    }
                    speakerShares
                    topTopics
                }
            }
        }
    }

    private func insightLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)
            Spacer()
            Text(value)
                .font(DS.FontToken.metadata.monospacedDigit())
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
    }

    @ViewBuilder
    private var speakerShares: some View {
        ForEach(model.insights.speakerShares.prefix(4), id: \.speaker) { share in
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(share.speaker)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int((share.share * 100).rounded()))%")
                        .font(DS.FontToken.metadata.monospacedDigit())
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
                LiquidProgressLine(value: share.share, color: DS.ColorToken.accentCyan)
            }
        }
    }

    @ViewBuilder
    private var topTopics: some View {
        if !model.insights.topTerms.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("TOP TOPICS")
                    .font(DS.FontToken.caption)
                    .kerning(0.6)
                    .foregroundStyle(DS.ColorToken.textMuted)
                // Wrapping pill rows; the adaptive grid keeps short terms packed.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 64), spacing: DS.Space.xs)],
                    alignment: .leading, spacing: DS.Space.xs
                ) {
                    ForEach(model.insights.topTerms, id: \.self) { term in
                        LiquidPill(term, color: DS.ColorToken.accentPurple)
                    }
                }
            }
        }
    }

    // MARK: - Next Meeting

    /// Next upcoming meeting by `startedAt > now` — real store read; the CTA
    /// opens it in this screen. The mockup's "add talking points" has no
    /// backing surface and is omitted.
    @ViewBuilder
    private var nextMeetingCard: some View {
        LiquidGlassCard("Next Meeting") {
            if let next = model.nextMeeting {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(next.title)
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: DS.Space.xxs) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.ColorToken.textMuted)
                        Text(LiquidMeetingsFormat.dayAndTime.string(from: next.startedAt))
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                    actionRow(systemImage: "arrow.right", title: "Open meeting") {
                        router.navigate(to: next.id)
                    }
                }
            } else {
                inspectorEmpty("No upcoming meetings scheduled.")
            }
        }
    }

    private func inspectorEmpty(_ text: String) -> some View {
        Text(text)
            .font(DS.FontToken.metadata)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
