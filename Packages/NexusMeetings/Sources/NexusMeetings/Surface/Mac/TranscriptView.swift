import Combine
import Foundation
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

@MainActor
public final class TranscriptViewModel: ObservableObject {
    @Published public private(set) var segments: [MeetingSpeakerSegment] = []
    @Published public private(set) var participants: [MeetingParticipant] = []
    /// Distinct names used in prior meetings, offered as rename suggestions.
    @Published public private(set) var priorParticipantNames: [String] = []
    /// Ranked candidates seeded from this meeting's calendar attendees (#4b / I3): a
    /// *suggestion* surface for labeling, never auto-assigned to a speaker.
    @Published public private(set) var attendeeSuggestions: [MeetingAttendeeCandidate] = []
    /// Existing contacts the user can assign a speaker to (#3). A picked `Person`
    /// records `personID` + `displayName`; loaded only when a `PersonRepository` is
    /// wired (graph-only — no People UI module import).
    @Published public private(set) var people: [Person] = []

    private let meetingID: UUID
    private let repository: MeetingRepository
    private let peopleLinker: MeetingPeopleLinker?
    private let personRepository: PersonRepository?
    private let attendeeSeedProvider: (@MainActor (Meeting) async -> [MeetingAttendeeCandidate])?
    private let merge = MergeStage()

    public init(
        meetingID: UUID,
        repository: MeetingRepository,
        peopleLinker: MeetingPeopleLinker? = nil,
        personRepository: PersonRepository? = nil,
        attendeeSeedProvider: (@MainActor (Meeting) async -> [MeetingAttendeeCandidate])? = nil
    ) {
        self.meetingID = meetingID
        self.repository = repository
        self.peopleLinker = peopleLinker
        self.personRepository = personRepository
        self.attendeeSeedProvider = attendeeSeedProvider
    }

    public var speakerNames: Set<String> {
        Set(segments.map(\.speaker))
    }

    public func load() {
        priorParticipantNames = (try? repository.distinctParticipantNames()) ?? []
        people = (try? personRepository?.allActive()) ?? []

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

    /// Resolves a calendar candidate to an existing `Person` by email
    /// (case-insensitive), used so picking an invitee can assign a real contact when
    /// one already exists. Returns `nil` when the candidate has no email or no
    /// matching contact (the sheet then pre-fills the name as free text).
    public func existingPerson(forCandidate candidate: MeetingAttendeeCandidate) -> Person? {
        guard let email = candidate.email?.lowercased(), !email.isEmpty else { return nil }
        return people.first { ($0.email?.lowercased()).map { $0 == email } ?? false }
    }

    public func displayName(for speaker: String) -> String {
        participants.first { $0.speakerID == speaker }?.displayName ?? speaker
    }

    /// Free-text rename: labels the speaker with arbitrary text and CLEARS any prior
    /// `personID` (re-labeling to plain text means "not that tracked contact").
    public func rename(speaker: String, to displayName: String) throws {
        try rename(speaker: speaker, displayName: displayName, personID: nil)
    }

    /// Assigns the speaker to an existing `Person` (#3): records both `personID` and
    /// the person's `displayName`. The linker keys off `personID`, wiring the
    /// `.attendee` edge to exactly this person (no name soft-match).
    public func rename(speaker: String, to person: Person) throws {
        try rename(speaker: speaker, displayName: person.displayName, personID: person.id)
    }

    private func rename(speaker: String, displayName: String, personID: UUID?) throws {
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else { return }
        guard let meeting = try repository.find(id: meetingID) else { return }

        let currentParticipants = try MeetingParticipant.decode(meeting.participantsJSON ?? Data())
        var nextParticipants = currentParticipants.filter { $0.speakerID != speaker }
        nextParticipants.append(
            MeetingParticipant(speakerID: speaker, displayName: trimmedDisplayName, personID: personID)
        )
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
        personRepository: PersonRepository? = nil,
        attendeeSeedProvider: (@MainActor (Meeting) async -> [MeetingAttendeeCandidate])? = nil
    ) {
        self.isReadOnly = isReadOnly
        _viewModel = StateObject(
            wrappedValue: TranscriptViewModel(
                meetingID: meetingID,
                repository: repository,
                peopleLinker: peopleLinker,
                personRepository: personRepository,
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
                people: viewModel.people,
                attendeeSuggestions: viewModel.attendeeSuggestions,
                suggestions: viewModel.priorParticipantNames,
                existingPersonForCandidate: { viewModel.existingPerson(forCandidate: $0) },
                onCancel: {
                    renaming = nil
                    renameDraft = ""
                    renameError = nil
                },
                onSavePerson: { person in
                    guard let speaker = renaming else { return }
                    do {
                        try viewModel.rename(speaker: speaker, to: person)
                        renaming = nil
                        renameDraft = ""
                        renameError = nil
                    } catch {
                        renameError = error.localizedDescription
                    }
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
    /// Existing contacts to assign the speaker to (#3). Picking one assigns a real
    /// `Person` (personID + displayName); the `TextField` below stays as the
    /// "create a new contact / free-text" fallback.
    let people: [Person]
    let attendeeSuggestions: [MeetingAttendeeCandidate]
    let suggestions: [String]
    /// Resolves an invite candidate to an existing `Person` by email, when one exists.
    let existingPersonForCandidate: (MeetingAttendeeCandidate) -> Person?
    let onCancel: () -> Void
    /// Assigns the speaker to an existing `Person` (records personID + displayName).
    let onSavePerson: (Person) -> Void
    /// Saves the current free-text draft as a plain label (clears any personID).
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

    private func matches(_ haystack: String) -> Bool {
        let needle = trimmedDraft
        guard !needle.isEmpty else { return true }
        return haystack.range(
            of: needle,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    /// Existing contacts matching the draft (name or email), capped.
    private var filteredPeople: [Person] {
        Array(
            people.filter { matches($0.displayName) || matches($0.email ?? "") }
                .prefix(6)
        )
    }

    private var filteredSuggestions: [String] { filtered(suggestions) }

    /// Ranked calendar attendees of *this* meeting (#4b / I3), filtered by the draft.
    private var filteredAttendeeSuggestions: [MeetingAttendeeCandidate] {
        Array(
            attendeeSuggestions.filter { matches($0.name) || matches($0.email ?? "") }
                .prefix(6)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Assign Speaker")
                .font(.headline)

            Text(speaker)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Name (or create a new contact)", text: $draft)
                .textFieldStyle(.roundedBorder)

            if !filteredPeople.isEmpty {
                peopleSection
            }

            if !filteredAttendeeSuggestions.isEmpty {
                attendeeSection
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

    /// Existing contacts — picking a row assigns a real `Person` (#3).
    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Contacts")
                .font(.caption2)
                .foregroundStyle(NexusColor.Text.muted)

            ForEach(filteredPeople) { person in
                Button {
                    onSavePerson(person)
                } label: {
                    personRow(name: person.displayName, email: person.email, hint: nil)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Assign this contact")
            }
        }
    }

    /// Ranked invite candidates — picking one assigns the matching contact when an
    /// email match exists, otherwise pre-fills the draft so Save creates a contact.
    private var attendeeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("From this meeting's invite")
                .font(.caption2)
                .foregroundStyle(NexusColor.Text.muted)

            ForEach(filteredAttendeeSuggestions) { candidate in
                Button {
                    if let person = existingPersonForCandidate(candidate) {
                        onSavePerson(person)
                    } else {
                        draft = candidate.name
                    }
                } label: {
                    personRow(name: candidate.name, email: candidate.email, hint: candidate.statusHint)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Use this attendee")
            }
        }
    }

    @ViewBuilder
    private func personRow(name: String, email: String?, hint: String?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle")
                .font(.body)
                .foregroundStyle(NexusColor.Text.tertiary)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(NexusColor.Text.primary)
                    if let hint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(NexusColor.Text.muted)
                    }
                }
                if let email, !email.isEmpty {
                    Text(email)
                        .font(.caption2)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
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
