import Foundation
import NexusCore

@MainActor
enum LiquidTodayReferenceData {
    struct Snapshot {
        let agendaItems: [LiquidAgendaItem]
        /// Raw calendar events for the Up Next card (selector filters + caps at render time).
        let events: [CalendarEvent]
        let priorityGroups: [LiquidPriorityGroup]
        let projects: [LiquidProjectProgress]
        let meetingIntel: LiquidTodayMeetingIntel?
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

        let agendaItems = [
            LiquidAgendaItem(
                id: "deep-work", title: "Deep Work", subtitle: "Product Strategy", start: at(9), end: at(9, 50), isAllDay: false,
                kind: .focus),
            LiquidAgendaItem(
                id: "one-one", title: "1:1 Meeting", subtitle: "Jamie Park", start: at(10), end: at(10, 50), isAllDay: false, kind: .meeting
            ),
            LiquidAgendaItem(
                id: "roadmap-review", title: "Product Roadmap Review", subtitle: "Conference Room B", start: at(11), end: at(12),
                isAllDay: false, kind: .project),
            LiquidAgendaItem(
                id: "focus-time", title: "Focus Time", subtitle: "Design System Audit", start: at(13), end: at(14), isAllDay: false,
                kind: .focus),
            LiquidAgendaItem(
                id: "marketing-sync", title: "Marketing Sync", subtitle: "Go-to-Market Plan", start: at(14, 30), end: at(15, 15),
                isAllDay: false, kind: .meeting),
            LiquidAgendaItem(
                id: "leadership", title: "Leadership Update", subtitle: "Weekly Check-in", start: at(16), end: at(16, 45), isAllDay: false,
                kind: .personal),
        ]

        // Reference calendar events for the Up Next card: staggered-hour events
        // that cover the populated, capped, and "+N more" states in previews.
        let referenceEvents = [
            CalendarEvent(id: "ref-e10", title: "1:1 Meeting", start: at(10), end: at(10, 50)),
            CalendarEvent(id: "ref-e11", title: "Product Roadmap Review", start: at(11), end: at(12)),
            CalendarEvent(id: "ref-e13", title: "Focus Time", start: at(13), end: at(14)),
            CalendarEvent(id: "ref-e14", title: "Marketing Sync", start: at(14, 30), end: at(15, 15)),
        ]

        return Snapshot(
            agendaItems: agendaItems,
            events: referenceEvents,
            priorityGroups: LiquidTodayModel.priorityGroups(overdue: [], today: tasks),
            projects: [
                LiquidProjectProgress(project: roadmap, doneCount: 17, totalCount: 25),
                LiquidProjectProgress(project: assistant, doneCount: 10, totalCount: 24),
                LiquidProjectProgress(project: design, doneCount: 18, totalCount: 24),
            ],
            meetingIntel: LiquidTodayMeetingIntel(
                title: "Product Roadmap Review",
                occurredAt: at(11),
                durationSec: 50 * 60,
                summary:
                    // swiftlint:disable:next line_length
                    "Reviewed Q2 roadmap progress, confirmed priority bets, and aligned on resourcing for AI Assistant and mobile improvements.",
                decisions: ["Move AI Assistant to top priority", "Launch beta in early July"],
                actionItemCount: 3,
                statusLabel: "Processed"
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
