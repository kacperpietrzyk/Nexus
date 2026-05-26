import SwiftData
import SwiftUI

#if os(iOS)
public struct iOSMeetingsListView: View {  // swiftlint:disable:this type_name
    private let composition: MeetingsComposition

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        NavigationStack {
            IOSMeetingsListContentView(composition: composition)
        }
    }
}

struct IOSMeetingsListContentView: View {
    private let composition: MeetingsComposition
    @State private var meetings: [Meeting] = []

    init(composition: MeetingsComposition) {
        self.composition = composition
    }

    var body: some View {
        List {
            if meetings.isEmpty {
                ContentUnavailableView(
                    "No meetings",
                    systemImage: "person.wave.2",
                    description: Text("Recorded meetings will appear here.")
                )
            } else {
                ForEach(meetings, id: \.id) { meeting in
                    NavigationLink {
                        iOSMeetingDetailView(
                            meetingID: meeting.id,
                            composition: composition
                        )
                    } label: {
                        IOSMeetingRow(meeting: meeting)
                    }
                }
            }
        }
        .navigationTitle("Meetings")
        .refreshable {
            reload()
        }
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
    }

    private func reload() {
        meetings = ((try? composition.meetingRepository.allChronological()) ?? [])
            .filter { $0.deletedAt == nil }
    }
}

private struct IOSMeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !meeting.actionItemIDs.isEmpty {
                    Label("\(meeting.actionItemIDs.count)", systemImage: "checklist")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
