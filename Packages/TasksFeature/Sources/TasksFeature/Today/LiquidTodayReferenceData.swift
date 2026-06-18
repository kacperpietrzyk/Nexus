import Foundation
import NexusCore

@MainActor
enum LiquidTodayReferenceData {
    struct Snapshot {
        /// Raw calendar events for the Up Next card (selector filters + caps at render time).
        let events: [CalendarEvent]
        let priorityGroups: [LiquidPriorityGroup]
        let projects: [LiquidProjectProgress]
        let decisions: [LiquidTodayDecision]
        let pinnedFocusTask: TaskItem?
        let projectNamesByID: [UUID: String]
        let focusSuggestion: DateInterval?
        let brief: String
    }

    // swiftlint:disable:next function_body_length
    static func snapshot(now: Date) -> Snapshot {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: .minute, value: hour * 60 + minute, to: dayStart) ?? dayStart
        }

        let roadmap = Project(name: "Product Roadmap", color: "spark", status: .active)
        let assistant = Project(name: "AI Assistant", color: "bolt", status: .active)
        let design = Project(name: "Design System", color: "layers", status: .active)

        let tasks = [
            TaskItem(title: "Finalize Q2 roadmap", dueAt: now, priority: .high, projectID: roadmap.id),
            TaskItem(title: "Review PRD: AI Assistant", dueAt: now, priority: .high, projectID: assistant.id),
            TaskItem(title: "Align on GTM messaging", dueAt: now.addingTimeInterval(86_400), priority: .high),
            TaskItem(title: "User research analysis", dueAt: now.addingTimeInterval(3 * 86_400), priority: .medium),
            TaskItem(title: "Design system audit", dueAt: now.addingTimeInterval(3 * 86_400), priority: .medium, projectID: design.id),
            TaskItem(title: "Update help center", dueAt: now.addingTimeInterval(4 * 86_400), priority: .medium),
            TaskItem(title: "Prep for board update", dueAt: now.addingTimeInterval(6 * 86_400), priority: .low),
        ]

        let pinned = TaskItem(
            title: "Deep Work",
            dueAt: at(10),
            startAt: now.addingTimeInterval(-42 * 60),
            endAt: now.addingTimeInterval(58 * 60),
            priority: .high,
            projectID: roadmap.id,
            pinnedAsFocus: true
        )

        // Reference calendar events for the Up Next card: now-relative offsets so
        // the populated, capped, and "+N more" states are always visible regardless
        // of the wall-clock time at which a screenshot or preview is taken.
        let referenceEvents = [
            CalendarEvent(
                id: "ref-e1",
                title: "1:1 Meeting",
                start: now.addingTimeInterval(30 * 60),
                end: now.addingTimeInterval(80 * 60)
            ),
            CalendarEvent(
                id: "ref-e2",
                title: "Product Roadmap Review",
                start: now.addingTimeInterval(90 * 60),
                end: now.addingTimeInterval(150 * 60)
            ),
            CalendarEvent(
                id: "ref-e3",
                title: "Focus Time",
                start: now.addingTimeInterval(3 * 60 * 60),
                end: now.addingTimeInterval(4 * 60 * 60)
            ),
            CalendarEvent(
                id: "ref-e4",
                title: "Marketing Sync",
                start: now.addingTimeInterval(270 * 60),
                end: now.addingTimeInterval(315 * 60)
            ),
        ]

        return Snapshot(
            events: referenceEvents,
            priorityGroups: LiquidTodayModel.priorityGroups(overdue: [], today: tasks),
            projects: [
                LiquidProjectProgress(project: roadmap, doneCount: 17, totalCount: 25),
                LiquidProjectProgress(project: assistant, doneCount: 10, totalCount: 24),
                LiquidProjectProgress(project: design, doneCount: 18, totalCount: 24),
            ],
            decisions: LiquidTodayModel.aggregateDecisions(
                [
                    LiquidTodayMeetingDecisions(
                        meetingID: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890") ?? UUID(),
                        meetingTitle: "Product Roadmap Review",
                        meetingDate: at(11),
                        decisions: ["Move AI Assistant to top priority", "Launch beta in early July"]
                    ),
                    LiquidTodayMeetingDecisions(
                        meetingID: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901") ?? UUID(),
                        meetingTitle: "Design System Sync",
                        meetingDate: at(11).addingTimeInterval(-86_400),
                        decisions: ["Adopt liquid card tokens globally", "Ship DS v2 by end of sprint"]
                    ),
                ],
                cap: 5
            ),
            pinnedFocusTask: pinned,
            projectNamesByID: [
                roadmap.id: roadmap.name,
                assistant.id: assistant.name,
                design.id: design.name,
            ],
            focusSuggestion: DateInterval(start: at(14), end: at(16)),
            brief:
                // swiftlint:disable:next line_length
                "Good morning. You have a busy day with 6 meetings and 3 priorities due today.\n\nProtect the 2h focus block and close the roadmap review follow-ups."
        )
    }
}
