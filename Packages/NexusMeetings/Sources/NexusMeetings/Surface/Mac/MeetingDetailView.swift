import Foundation
import SwiftUI

#if os(macOS)
public struct MeetingDetailView: View {
    private let meetingID: UUID
    private let composition: MeetingsComposition
    private let onDeleted: (() -> Void)?

    @State private var meeting: Meeting?
    @State private var selectedTab: Tab = .transcript
    @State private var titleDraft: String = ""

    enum Tab: Hashable {
        case transcript
        case summary
        case actions
        case audio
    }

    public init(
        meetingID: UUID,
        composition: MeetingsComposition,
        onDeleted: (() -> Void)? = nil
    ) {
        self.meetingID = meetingID
        self.composition = composition
        self.onDeleted = onDeleted
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabContent
        }
        .toolbar {
            MeetingDetailToolbar(
                meetingID: meetingID,
                composition: composition,
                onDeleted: onDeleted
            )
        }
        .onAppear {
            reload()
        }
        .onChange(of: meetingID) { _, _ in
            saveTitle()
            reload()
        }
        .onDisappear {
            saveTitle()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("Meeting title", text: $titleDraft)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .onSubmit {
                        saveTitle()
                    }
                    .onDisappear {
                        saveTitle()
                    }

                Spacer()

                if let meeting {
                    Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Meeting detail tab", selection: $selectedTab) {
                Text("Transcript").tag(Tab.transcript)
                Text("Summary").tag(Tab.summary)
                Text("Action items").tag(Tab.actions)
                Text("Audio").tag(Tab.audio)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(16)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .transcript:
            TranscriptView(meetingID: meetingID, repository: composition.meetingRepository)
        case .summary:
            SummaryView(meetingID: meetingID, repository: composition.meetingRepository)
        case .actions:
            ActionItemsTabView(meetingID: meetingID, composition: composition)
        case .audio:
            let storage = try? composition.audioStorageRepository.find(meetingID: meetingID)
            let folderURL = storage?.folderURL ?? URL(fileURLWithPath: "/tmp")
            AudioTabView(
                meURL: folderURL.appendingPathComponent("me.wav"),
                othersURL: folderURL.appendingPathComponent("others.wav"),
                hasAudio: storage?.hasAudio ?? false
            )
        }
    }

    private func reload() {
        let loadedMeeting = try? composition.meetingRepository.find(id: meetingID)
        meeting = loadedMeeting
        titleDraft = loadedMeeting?.title ?? ""
    }

    private func saveTitle() {
        let nextTitle = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextTitle.isEmpty else {
            titleDraft = meeting?.title ?? ""
            return
        }
        guard let meeting, meeting.title != nextTitle else { return }
        guard let current = try? composition.meetingRepository.find(id: meeting.id) else { return }

        current.title = nextTitle
        current.updatedAt = Date()

        do {
            try composition.meetingRepository.upsert(current)
            self.meeting = current
        } catch {
            titleDraft = meeting.title
        }
    }
}
#endif
