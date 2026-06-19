import Foundation
import NexusCore
import NexusUI
import Testing

@testable import TasksFeature

// MARK: - MP-2 row idiom: TaskStatus → NexusStatus mapping + DeadlineBadge neutral

@Suite("TaskRowView MP-2 — status mapping")
struct TaskRowViewMP2Tests {

    // MARK: TaskStatus → NexusStatus mapping
    // Uses the module-scope `taskNexusStatus(for:)` — not @MainActor, directly testable.

    @Test("open task maps to .todo")
    func openMapsToTodo() {
        #expect(taskNexusStatus(for: .open) == .todo)
    }

    @Test("done task maps to .done")
    func doneMapsToDone() {
        #expect(taskNexusStatus(for: .done) == .done)
    }

    @Test("snoozed task maps to .inReview")
    func snoozedMapsToInReview() {
        #expect(taskNexusStatus(for: .snoozed) == .inReview)
    }

    @Test("all TaskStatus cases are covered (exhaustive switch guard)")
    func allCasesCovered() {
        for status in TaskStatus.allCases {
            let nexusStatus = taskNexusStatus(for: status)
            // Exhaustive on TaskStatus (no `default`) — a new TaskStatus case
            // is a compile error here, matching the production guarantee. The
            // expected NexusStatus is matched exhaustively too: any other
            // NexusStatus for a given TaskStatus records an Issue.
            switch status {
            case .open:
                switch nexusStatus {
                case .todo: break
                case .inProgress, .inReview, .done, .cancelled:
                    Issue.record("open must map to .todo, got \(nexusStatus)")
                }
            case .done:
                switch nexusStatus {
                case .done: break
                case .todo, .inProgress, .inReview, .cancelled:
                    Issue.record("done must map to .done, got \(nexusStatus)")
                }
            case .snoozed:
                switch nexusStatus {
                case .inReview: break
                case .todo, .inProgress, .done, .cancelled:
                    Issue.record("snoozed must map to .inReview, got \(nexusStatus)")
                }
            }
        }
    }
}

// MARK: - DeadlineBadge always-neutral for 1…3 day window

@Suite("DeadlineBadgeFormatter MP-2 — always neutral for near future")
struct DeadlineBadgeMP2NeutralTests {
    let now = ISO8601DateFormatter().date(from: "2026-05-04T12:00:00Z")!
    var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .gmt
        return cal
    }

    @Test("deadline in 1-3 days returns neutral tone (not accent)")
    func nearFutureDeadlineIsNeutral() {
        for days in 1...3 {
            let deadline = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
            let presentation = DeadlineBadgeFormatter.presentation(
                deadlineAt: deadline,
                now: now,
                calendar: calendar
            )
            #expect(
                presentation?.tone == .neutral,
                "Expected .neutral for \(days)d deadline, got \(String(describing: presentation?.tone))"
            )
            #expect(
                presentation?.tone != .accent,
                "Accent must be burned off for \(days)d deadline"
            )
        }
    }

    @Test("deadline in 4+ days still returns neutral tone")
    func farFutureDeadlineIsNeutral() {
        for days in 4...7 {
            let deadline = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
            let presentation = DeadlineBadgeFormatter.presentation(
                deadlineAt: deadline,
                now: now,
                calendar: calendar
            )
            #expect(presentation?.tone == .neutral, "Expected .neutral for \(days)d deadline")
        }
    }
}

// MARK: - Project pill visibility (Task 2)

@Suite("TaskRowView — project pill visibility")
struct TaskRowProjectPillTests {

    @Test("Project pill text is shown verbatim when provided")
    func projectPillShownWhenNamePresent() {
        #expect(TaskRowProjectPill.label(for: "CyberLab") == "CyberLab")
    }

    @Test("No project pill when name is nil")
    func projectPillHiddenWhenNil() {
        #expect(TaskRowProjectPill.label(for: nil as String?) == nil)
    }
}

// MARK: - Due/deadline dedupe precedence (Linear redesign)

@Suite("TaskRowView — due/deadline dedupe precedence")
struct DueDeadlineDedupeTests {

    private func roseDeadline(_ label: String, kind: DeadlineUrgency) -> DeadlineBadgePresentation {
        DeadlineBadgePresentation(label: label, tone: .rose, kind: kind)
    }

    @Test("overdue due + missed (rose) deadline → suppress the deadline chip (due wins)")
    func overdueDueSuppressesRoseDeadline() {
        #expect(
            suppressesDeadlineChip(
                due: .overdue(daysLate: 3),
                deadline: roseDeadline("deadline missed", kind: .missed)
            ) == true
        )
    }

    @Test("overdue due + TODAY (rose) deadline → keep the deadline chip (distinct, more-urgent fact)")
    func overdueDueKeepsTodayDeadline() {
        // Regression: due slipped days ago but the hard deadline is TODAY. Both
        // render rose, yet "deadline today" is the more urgent fact and must NOT
        // be hidden. Suppression keys on `.missed`, not on tone, so this is kept.
        #expect(
            suppressesDeadlineChip(
                due: .overdue(daysLate: 2),
                deadline: roseDeadline("deadline today", kind: .today)
            ) == false
        )
    }

    @Test("overdue due + neutral future deadline → keep the deadline chip (distinct signal)")
    func overdueDueKeepsNeutralDeadline() {
        #expect(
            suppressesDeadlineChip(
                due: .overdue(daysLate: 5),
                deadline: DeadlineBadgePresentation(label: "deadline in 4d", tone: .neutral, kind: .upcoming)
            ) == false
        )
    }

    @Test("today due + missed (rose) deadline → keep the deadline chip (due is not overdue)")
    func todayDueKeepsRoseDeadline() {
        #expect(
            suppressesDeadlineChip(
                due: .today(timeOfDay: nil),
                deadline: roseDeadline("deadline today", kind: .today)
            ) == false
        )
    }

    @Test("future due + no deadline → nothing to suppress")
    func futureDueNoDeadline() {
        #expect(
            suppressesDeadlineChip(
                due: .future(date: "4 Jun", timeOfDay: nil),
                deadline: nil
            ) == false
        )
    }
}
