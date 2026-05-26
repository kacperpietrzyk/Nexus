import Foundation
import SwiftData
import SwiftUI

#if os(iOS)
public struct iOSMeetingDetailView: View {  // swiftlint:disable:this type_name
    private let meetingID: UUID
    private let composition: MeetingsComposition

    @State private var meeting: Meeting?
    @State private var selectedTab: Tab = .summary

    private enum Tab: Hashable {
        case summary
        case transcript
        case actions
    }

    public init(meetingID: UUID, composition: MeetingsComposition) {
        self.meetingID = meetingID
        self.composition = composition
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Meeting detail tab", selection: $selectedTab) {
                Text("Summary").tag(Tab.summary)
                Text("Transcript").tag(Tab.transcript)
                Text("Actions").tag(Tab.actions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            tabContent
        }
        .navigationTitle(meeting?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .summary:
            SummaryView(
                meetingID: meetingID,
                repository: composition.meetingRepository,
                isReadOnly: true
            )
        case .transcript:
            TranscriptView(
                meetingID: meetingID,
                repository: composition.meetingRepository,
                isReadOnly: true
            )
        case .actions:
            ActionItemsTabView(meetingID: meetingID, composition: composition)
        }
    }

    private func reload() {
        meeting = try? composition.meetingRepository.find(id: meetingID)
    }
}
#endif
