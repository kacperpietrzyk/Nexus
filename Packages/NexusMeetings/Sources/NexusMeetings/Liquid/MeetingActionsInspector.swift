#if os(macOS)
import AppKit
import Foundation
import NexusCore
import NexusUI
import SwiftUI

/// Right inspector for the Meetings screen (spec §Right inspector), 304 pt.
/// Fixed section order (top→bottom):
///   1. Processing — conditional, in-flight pipeline only.
///   2. People (ANCHOR) — attendees + linked people + assign cue.
///   3. Insights (ANCHOR) — aggregates.
///   4. Follow-ups — open action items; hidden when empty.
///   5. Related — notes + backlinks; hidden when both empty.
///   6. Next Meeting — hidden when no upcoming meeting.
public struct MeetingActionsInspector: View {

    private let model: LiquidMeetingsModel
    private let composition: MeetingsComposition
    @ObservedObject private var router: MeetingNavigationRouter
    private let navigation: LiquidMeetingsNavigation

    // MARK: - Inline speaker assign sheet state

    /// The raw speaker ID being assigned (e.g. `"Speaker_1"`). Non-nil while
    /// the `RenameSpeakerSheet` is presented from the People section.
    @State private var assigningSpeaker: String?
    @State private var assignDraft = ""
    @State private var assignError: String?

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
                // 1. Processing — conditional (in-flight pipeline only)
                if let meeting = model.meeting, shouldShowCancelCard(for: meeting) {
                    cancelProcessingCard(meeting)
                }

                if model.meeting != nil {
                    // 2. People — ANCHOR (always shown when a meeting is selected)
                    KnowledgeSections(
                        model: model, composition: composition, router: router,
                        navigation: navigation,
                        onAssignSpeaker: { rawSpeaker in
                            assigningSpeaker = rawSpeaker
                            assignDraft = rawSpeaker
                            assignError = nil
                        }
                    ).peopleSection

                    // 3. Insights — ANCHOR
                    insightsCard

                    // 4. Follow-ups — empty-hides
                    if !model.openActionItems.isEmpty {
                        followUpCard
                    }

                    // 5. Related (notes + backlinks) — empty-hides
                    KnowledgeSections(
                        model: model, composition: composition, router: router,
                        navigation: navigation
                    ).relatedSection

                    // 6. Next Meeting — empty-hides
                    if let next = model.nextMeeting {
                        nextMeetingCard(next)
                    }
                }
            }
            .padding(DS.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(
            isPresented: Binding(
                get: { assigningSpeaker != nil },
                set: { isPresented in
                    if !isPresented { dismissAssignSheet() }
                }
            )
        ) {
            assignSheet
        }
    }

    // MARK: - Inline speaker assign sheet

    @ViewBuilder
    private var assignSheet: some View {
        let people = (try? composition.personRepository.allActive()) ?? []
        let suggestions = (try? composition.meetingRepository.distinctParticipantNames()) ?? []
        RenameSpeakerSheet(
            speaker: assigningSpeaker ?? "",
            draft: $assignDraft,
            errorMessage: assignError,
            style: .liquid,
            people: people,
            attendeeSuggestions: [],
            suggestions: suggestions,
            existingPersonForCandidate: { _ in nil },
            onCancel: { dismissAssignSheet() },
            onSavePerson: { person in
                guard let rawSpeaker = assigningSpeaker else { return }
                model.assignSpeaker(
                    rawSpeaker: rawSpeaker,
                    displayName: person.displayName,
                    personID: person.id,
                    composition: composition
                )
                dismissAssignSheet()
            },
            onSave: {
                guard let rawSpeaker = assigningSpeaker else { return }
                let trimmed = assignDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                model.assignSpeaker(
                    rawSpeaker: rawSpeaker,
                    displayName: trimmed,
                    personID: nil,
                    composition: composition
                )
                dismissAssignSheet()
            }
        )
    }

    private func dismissAssignSheet() {
        assigningSpeaker = nil
        assignDraft = ""
        assignError = nil
    }

    // MARK: - Cancel processing

    private func shouldShowCancelCard(for meeting: Meeting) -> Bool {
        navigation.cancelProcessing != nil
            && MeetingProcessingStatus.isInFlight(meeting.processingStatus)
    }

    /// Shown only while the selected meeting is in-flight in the helper's
    /// pipeline (queued or a `processing-*` stage). Drives the helper's
    /// `PipelineQueue` over XPC via the host-provided `cancelProcessing` seam —
    /// the in-app surface for a cross-process cancel that an in-app queue can't
    /// reach.
    @ViewBuilder
    private func cancelProcessingCard(_ meeting: Meeting) -> some View {
        LiquidGlassCard("Processing") {
            VStack(spacing: DS.Space.xs) {
                actionRow(systemImage: "xmark.circle", title: "Cancel processing") {
                    navigation.cancelProcessing?(meeting.id)
                }
            }
        }
    }

    // MARK: - Follow-up Tasks

    /// Open action items of the selected meeting; only rendered when non-empty.
    @ViewBuilder
    private var followUpCard: some View {
        LiquidGlassCard("Follow-up Tasks") {
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
    /// opens it in this screen. Only rendered when a next meeting exists.
    @ViewBuilder
    private func nextMeetingCard(_ next: Meeting) -> some View {
        LiquidGlassCard("Next Meeting") {
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
        }
    }

    // MARK: - Shared affordances

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
