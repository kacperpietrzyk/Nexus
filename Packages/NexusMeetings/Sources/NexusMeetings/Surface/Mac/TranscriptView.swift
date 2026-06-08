import Combine
import Foundation
import NexusUI
import SwiftData
import SwiftUI

@MainActor
public final class TranscriptViewModel: ObservableObject {
    @Published public private(set) var segments: [MeetingSpeakerSegment] = []
    @Published public private(set) var participants: [MeetingParticipant] = []
    /// Distinct names used in prior meetings, offered as rename suggestions.
    @Published public private(set) var priorParticipantNames: [String] = []
    /// Names seeded from this meeting's calendar attendees (spec §5 / I3): a
    /// *suggestion* surface for labeling, never auto-assigned to a speaker.
    @Published public private(set) var attendeeSuggestions: [String] = []

    private let meetingID: UUID
    private let repository: MeetingRepository
    private let peopleLinker: MeetingPeopleLinker?
    private let attendeeSeedProvider: (@MainActor (Meeting) async -> [String])?
    private let merge = MergeStage()

    public init(
        meetingID: UUID,
        repository: MeetingRepository,
        peopleLinker: MeetingPeopleLinker? = nil,
        attendeeSeedProvider: (@MainActor (Meeting) async -> [String])? = nil
    ) {
        self.meetingID = meetingID
        self.repository = repository
        self.peopleLinker = peopleLinker
        self.attendeeSeedProvider = attendeeSeedProvider
    }

    public var speakerNames: Set<String> {
        Set(segments.map(\.speaker))
    }

    public func load() {
        priorParticipantNames = (try? repository.distinctParticipantNames()) ?? []

        guard let meeting = try? repository.find(id: meetingID) else {
            segments = []
            participants = []
            return
        }

        segments = (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? []
        participants = (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
    }

    /// Loads calendar-attendee name suggestions for the current meeting. These
    /// are merged into the rename sheet as *candidates only* — picking one is the
    /// user's manual choice (I3); nothing here writes `participantsJSON`.
    public func loadAttendeeSuggestions() async {
        guard let provider = attendeeSeedProvider,
            let meeting = try? repository.find(id: meetingID)
        else {
            attendeeSuggestions = []
            return
        }
        attendeeSuggestions = await provider(meeting)
    }

    public func displayName(for speaker: String) -> String {
        participants.first { $0.speakerID == speaker }?.displayName ?? speaker
    }

    public func rename(speaker: String, to displayName: String) throws {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else { return }
        guard let meeting = try repository.find(id: meetingID) else { return }

        let currentParticipants = try MeetingParticipant.decode(meeting.participantsJSON ?? Data())
        var nextParticipants = currentParticipants.filter { $0.speakerID != speaker }
        nextParticipants.append(MeetingParticipant(speakerID: speaker, displayName: trimmedDisplayName))
        nextParticipants.sort { $0.speakerID.localizedStandardCompare($1.speakerID) == .orderedAscending }

        meeting.participantsJSON = try MeetingParticipant.encode(nextParticipants)
        // Re-render the persisted transcript from the corrected segments so the
        // stored `transcriptText` (used by search/summary) substitutes the named
        // speakers, matching the view (spec §5: transcript projection substitutes).
        let storedSegments = (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? []
        meeting.transcriptText = merge.renderLinear(storedSegments, participants: nextParticipants)
        meeting.updatedAt = Date()
        try repository.upsert(meeting)
        participants = nextParticipants

        // Wire the (otherwise inert) People linker: a named speaker becomes a
        // `Person` + `.attendee` edge. Idempotent and graph-only — never an
        // assignee (I1). Runs at the labeling-save path because `participantsJSON`
        // is empty at pipeline time (names exist only after this manual step).
        // The hop re-fetches the meeting on the MainActor (the `Meeting` model is
        // not `Sendable`, so only the `UUID` crosses the task boundary).
        if let peopleLinker {
            let meetingID = meetingID
            Task { @MainActor [peopleLinker, repository] in
                guard let saved = try? repository.find(id: meetingID) else { return }
                _ = try? await peopleLinker.link(meeting: saved)
            }
        }
    }
}

public struct TranscriptView: View {
    @StateObject private var viewModel: TranscriptViewModel
    private let isReadOnly: Bool
    @State private var renaming: String?
    @State private var renameDraft = ""
    @State private var renameError: String?

    public init(
        meetingID: UUID,
        repository: MeetingRepository,
        isReadOnly: Bool = false,
        peopleLinker: MeetingPeopleLinker? = nil,
        attendeeSeedProvider: (@MainActor (Meeting) async -> [String])? = nil
    ) {
        self.isReadOnly = isReadOnly
        _viewModel = StateObject(
            wrappedValue: TranscriptViewModel(
                meetingID: meetingID,
                repository: repository,
                peopleLinker: peopleLinker,
                attendeeSeedProvider: attendeeSeedProvider
            )
        )
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(Array(viewModel.segments.enumerated()), id: \.offset) { _, segment in
                    TranscriptSegmentRow(
                        segment: segment,
                        displayName: viewModel.displayName(for: segment.speaker),
                        isReadOnly: isReadOnly,
                        onRename: {
                            renaming = segment.speaker
                            renameDraft = viewModel.displayName(for: segment.speaker)
                            renameError = nil
                        }
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            viewModel.load()
        }
        .task {
            await viewModel.loadAttendeeSuggestions()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            viewModel.load()
        }
        .sheet(
            isPresented: Binding(
                get: { renaming != nil },
                set: { isPresented in
                    if !isPresented {
                        renaming = nil
                        renameDraft = ""
                        renameError = nil
                    }
                }
            )
        ) {
            RenameSpeakerSheet(
                speaker: renaming ?? "",
                draft: $renameDraft,
                errorMessage: renameError,
                attendeeSuggestions: viewModel.attendeeSuggestions,
                suggestions: viewModel.priorParticipantNames,
                onCancel: {
                    renaming = nil
                    renameDraft = ""
                    renameError = nil
                },
                onSave: {
                    guard let speaker = renaming else { return }
                    let trimmedDraft = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    do {
                        try viewModel.rename(speaker: speaker, to: trimmedDraft)
                        renaming = nil
                        renameDraft = ""
                        renameError = nil
                    } catch {
                        renameError = error.localizedDescription
                    }
                }
            )
        }
    }
}

private struct TranscriptSegmentRow: View {
    let segment: MeetingSpeakerSegment
    let displayName: String
    let isReadOnly: Bool
    let onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Self.timestamp(from: segment.startMs))
                    .font(NexusType.metaMono)
                    .monospacedDigit()
                    .foregroundStyle(NexusColor.Text.disabled)

                if isReadOnly {
                    Text(displayName)
                        .font(Font.custom("Inter-Medium", size: 12))
                        .foregroundStyle(NexusColor.Text.secondary)
                } else {
                    Menu {
                        Button("Rename…", action: onRename)
                    } label: {
                        HStack(spacing: 4) {
                            Text(displayName)
                                .font(Font.custom("Inter-Medium", size: 12))
                                .foregroundStyle(NexusColor.Text.secondary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(NexusColor.Text.muted)
                        }
                    }
                    #if os(macOS)
                    .menuStyle(.borderlessButton)
                    #endif
                    .fixedSize()
                }
            }

            Text(segment.text)
                .font(NexusType.bodySmall)
                .foregroundStyle(NexusColor.Text.secondary)
                .textSelection(.enabled)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func timestamp(from milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1000)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private struct RenameSpeakerSheet: View {
    let speaker: String
    @Binding var draft: String
    let errorMessage: String?
    let attendeeSuggestions: [String]
    let suggestions: [String]
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Filters a candidate list against the current draft (case/diacritic-
    /// insensitive substring match; empty draft shows the full list; the exact
    /// current value is dropped; capped so the sheet can't grow unbounded).
    private func filtered(_ candidates: [String]) -> [String] {
        let needle = trimmedDraft
        let matches: [String]
        if needle.isEmpty {
            matches = candidates
        } else {
            matches = candidates.filter { candidate in
                candidate.caseInsensitiveCompare(needle) != .orderedSame
                    && candidate.range(
                        of: needle,
                        options: [.caseInsensitive, .diacriticInsensitive]
                    ) != nil
            }
        }
        return Array(matches.prefix(6))
    }

    private var filteredSuggestions: [String] { filtered(suggestions) }

    /// Calendar attendees of *this* meeting (spec §5 seed / I3), with any name
    /// already offered in the prior-meetings list removed so it isn't shown twice.
    private var filteredAttendeeSuggestions: [String] {
        let priorSet = Set(filteredSuggestions.map { $0.lowercased() })
        return filtered(attendeeSuggestions).filter { priorSet.contains($0.lowercased()) == false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Speaker")
                .font(.headline)

            Text(speaker)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Display name", text: $draft)
                .textFieldStyle(.roundedBorder)

            if !filteredAttendeeSuggestions.isEmpty {
                suggestionSection(
                    title: "From this meeting's invite",
                    names: filteredAttendeeSuggestions,
                    glyph: "calendar"
                )
            }

            if !filteredSuggestions.isEmpty {
                suggestionSection(
                    title: "From previous meetings",
                    names: filteredSuggestions,
                    glyph: "person.crop.circle"
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Status.danger)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedDraft.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    @ViewBuilder
    private func suggestionSection(title: String, names: [String], glyph: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(NexusColor.Text.muted)

            ForEach(names, id: \.self) { suggestion in
                Button {
                    draft = suggestion
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: glyph)
                            .font(.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                        Text(suggestion)
                            .font(.caption)
                            .foregroundStyle(NexusColor.Text.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Use this name")
            }
        }
    }
}
