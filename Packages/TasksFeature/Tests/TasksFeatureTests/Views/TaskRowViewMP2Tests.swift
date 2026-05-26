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
