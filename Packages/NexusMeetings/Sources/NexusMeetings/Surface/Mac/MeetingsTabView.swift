import NexusUI
import SwiftUI

#if os(macOS)
public struct MeetingsTabView: View {
    @ObservedObject private var router: MeetingNavigationRouter
    private let composition: MeetingsComposition
    @State private var hasVisibleMeetings = false

    public init(
        router: MeetingNavigationRouter,
        composition: MeetingsComposition
    ) {
        self.router = router
        self.composition = composition
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            MeetingsListView(
                repository: composition.meetingRepository,
                router: router,
                onItemsChanged: { hasVisibleMeetings = $0 }
            )
            .frame(width: 360)
            .padding(.leading, 14)
            .padding(.top, 22)
            .padding(.bottom, 18)

            if let id = router.selectedMeetingID {
                MeetingDetailView(
                    meetingID: id,
                    composition: composition,
                    onDeleted: {
                        router.selectedMeetingID = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MeetingsEmptyDetailState(hasVisibleMeetings: hasVisibleMeetings)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MeetingsEmptyDetailState: View {
    let hasVisibleMeetings: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(NexusColor.Text.muted)
            Text("Select a meeting")
                .font(Font.custom("Inter-SemiBold", size: 25))
                .foregroundStyle(NexusColor.Text.secondary)
            Text(
                hasVisibleMeetings
                    ? "Select a meeting from the list to view its notes and transcript."
                    : "Recordings and imports will appear on the left."
            )
            .font(NexusType.body)
            .foregroundStyle(NexusColor.Text.tertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
