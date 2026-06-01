import Combine
import Foundation
import NexusUI
import SwiftData
import SwiftUI

@MainActor
public final class TranscriptViewModel: ObservableObject {
    @Published public private(set) var segments: [MeetingSpeakerSegment] = []
    @Published public private(set) var participants: [MeetingParticipant] = []

    private let meetingID: UUID
    private let repository: MeetingRepository

    public init(meetingID: UUID, repository: MeetingRepository) {
        self.meetingID = meetingID
        self.repository = repository
    }

    public var speakerNames: Set<String> {
        Set(segments.map(\.speaker))
    }

    public func load() {
        guard let meeting = try? repository.find(id: meetingID) else {
            segments = []
            participants = []
            return
        }

        segments = (try? MeetingSpeakerSegment.decode(meeting.segmentsJSON)) ?? []
        participants = (try? MeetingParticipant.decode(meeting.participantsJSON ?? Data())) ?? []
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
        meeting.updatedAt = Date()
        try repository.upsert(meeting)
        participants = nextParticipants
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
        isReadOnly: Bool = false
    ) {
        self.isReadOnly = isReadOnly
        _viewModel = StateObject(
            wrappedValue: TranscriptViewModel(meetingID: meetingID, repository: repository)
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
    let onCancel: () -> Void
    let onSave: () -> Void

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
