import NexusUI
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
    @State private var undo = UndoController()

    init(composition: MeetingsComposition) {
        self.composition = composition
    }

    var body: some View {
        Group {
            if meetings.isEmpty {
                IOSMeetingsListEmptyState()
            } else {
                List {
                    ForEach(meetings, id: \.id) { meeting in
                        NavigationLink {
                            iOSMeetingDetailView(
                                meetingID: meeting.id,
                                composition: composition
                            )
                        } label: {
                            IOSMeetingRow(meeting: meeting)
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .leading) {
                            Button {
                                try? composition.meetingRepository.setPinned(meeting, !meeting.isPinned)
                                reload()
                            } label: {
                                Label(
                                    meeting.isPinned ? "Unpin" : "Pin to Today",
                                    systemImage: meeting.isPinned ? "star.slash" : "star"
                                )
                            }
                            .tint(meeting.isPinned ? .gray : .yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                softDelete(meeting)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                try? composition.meetingRepository.setPinned(meeting, !meeting.isPinned)
                                reload()
                            } label: {
                                Label(
                                    meeting.isPinned ? "Unpin from Today" : "Pin to Today",
                                    systemImage: meeting.isPinned ? "star.slash" : "star"
                                )
                            }

                            Divider()

                            Button {
                                copySummary(meeting)
                            } label: {
                                Label("Copy Summary as Markdown", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                softDelete(meeting)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        // Liquid: transparent root so the shell aurora reads behind the list.
        .background(Color.clear)
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
        .undoToast(undo)
    }

    // MARK: - Actions

    private func softDelete(_ meeting: Meeting) {
        meeting.deletedAt = Date()
        meeting.updatedAt = Date()
        try? composition.meetingRepository.context.save()
        reload()
        let meetingID = meeting.id
        undo.show(message: "Meeting deleted", icon: "trash") {
            meeting.deletedAt = nil
            meeting.updatedAt = Date()
            try? composition.meetingRepository.context.save()
            reload()
            _ = meetingID  // capture to keep alive
        }
    }

    private func copySummary(_ meeting: Meeting) {
        let sections = MeetingSummarySections.parse(summaryText: meeting.summaryText)
        var parts: [String] = []
        if let overview = sections.overview, !overview.isEmpty {
            parts.append(overview)
        }
        if !sections.decisions.isEmpty {
            parts.append("### Decisions\n\n" + sections.decisions.map { "- \($0)" }.joined(separator: "\n"))
        }
        for section in sections.extraSections {
            parts.append("### \(section.title)\n\n" + section.items.map { "- \($0)" }.joined(separator: "\n"))
        }
        let body = parts.joined(separator: "\n\n")
        let markdown = MarkdownExport.entity(
            title: meeting.title,
            body: body,
            metadata: [meeting.startedAt.formatted(date: .abbreviated, time: .shortened)]
        )
        PasteboardCopy.string(markdown)
    }

    private func reload() {
        meetings = ((try? composition.meetingRepository.allChronological()) ?? [])
            .filter { $0.deletedAt == nil }
    }
}

private struct IOSMeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NexusColor.Text.muted)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(Font.custom("Inter-Medium", size: 13))
                    .foregroundStyle(NexusColor.Text.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(meeting.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(NexusType.metaMono)
                        .monospacedDigit()
                        .foregroundStyle(NexusColor.Text.disabled)

                    if !meeting.actionItemIDs.isEmpty {
                        Label("\(meeting.actionItemIDs.count)", systemImage: "checklist")
                            .font(NexusType.meta)
                            .foregroundStyle(NexusColor.Text.muted)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IOSMeetingsListEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(NexusColor.Text.muted)
            Text("No meetings")
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.secondary)
            Text("Recorded meetings will appear here.")
                .font(NexusType.meta)
                .foregroundStyle(NexusColor.Text.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
