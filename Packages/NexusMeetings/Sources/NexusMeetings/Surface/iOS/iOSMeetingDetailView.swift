import Foundation
import NexusUI
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
            NexusSegmentedControl(
                items: [
                    .init(id: Tab.summary, label: "Summary"),
                    .init(id: Tab.transcript, label: "Transcript"),
                    .init(id: Tab.actions, label: "Actions"),
                ],
                selection: $selectedTab
            )
            .padding()

            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(height: 1)

            tabContent
        }
        // Liquid: transparent so the shell aurora reads behind the detail.
        .background(Color.clear)
        .navigationTitle(meeting?.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let meeting {
                ToolbarItem(placement: .topBarTrailing) {
                    // Same document the Mac detail pane shares — system share
                    // sheet via ShareLink (C1 parity). Default ShareLink label
                    // (share icon) matches the platform idiom.
                    ShareLink(
                        item: meeting.exportMarkdownDocument(
                            in: composition.meetingRepository.context)
                    )
                    .accessibilityLabel("Share meeting as Markdown")
                }
            }
        }
        .onAppear {
            reload()
        }
        // Also refresh on remote/cross-process store changes (CloudKit imports and
        // helper-process writes post .NSPersistentStoreRemoteChange, not didSave).
        .reloadOnStoreChange { reload() }
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
