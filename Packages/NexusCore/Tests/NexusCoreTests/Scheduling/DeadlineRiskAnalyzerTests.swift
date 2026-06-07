import Foundation
import Testing

@testable import NexusCore

@Suite("DeadlineRiskAnalyzer")
struct DeadlineRiskAnalyzerTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 8) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: TimeZone(identifier: "UTC"),
            year: 2026, month: 6, day: day, hour: hour, minute: minute
        ).date!
    }

    private var prefs: CalendarPreferences {
        CalendarPreferences(
            workdayStart: DateComponents(hour: 9, minute: 0),
            workdayEnd: DateComponents(hour: 18, minute: 0),
            minBlockMinutes: 15,
            maxBlockMinutes: 120,
            bufferMinutes: 0
        )
    }

    private struct FixedEstimator: DurationEstimator {
        let seconds: Int
        func estimate(for task: TaskItem, history: [TaskItem]) -> DurationEstimate {
            DurationEstimate(seconds: seconds, confidence: 1.0)
        }
    }

    private let horizon: TimeInterval = 14 * 24 * 3600

    @Test("task without a deadline produces no risk")
    func noDeadlineNoRisk() {
        let analyzer = DeadlineRiskAnalyzer()
        let task = TaskItem(title: "no deadline")
        let risks = analyzer.analyze(
            tasks: [task],
            events: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 3600),
            horizon: horizon,
            now: at(9),
            calendar: calendar
        )
        #expect(risks.isEmpty)
    }

    @Test("deadline beyond the horizon is not analyzed")
    func beyondHorizonExcluded() {
        let analyzer = DeadlineRiskAnalyzer()
        let task = TaskItem(title: "far", deadlineAt: at(9, day: 30))  // > 14 days out
        let risks = analyzer.analyze(
            tasks: [task],
            events: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 3600),
            horizon: horizon,
            now: at(9),
            calendar: calendar
        )
        #expect(risks.isEmpty)
    }

    @Test("ample free time before deadline → onTrack, no suggestedStartBy")
    func onTrack() {
        let analyzer = DeadlineRiskAnalyzer()
        // 1h of work, deadline end of tomorrow → ~18h free → big slack.
        let task = TaskItem(title: "easy", deadlineAt: at(17, day: 9))
        let risks = analyzer.analyze(
            tasks: [task],
            events: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 3600),
            horizon: horizon,
            now: at(9),
            calendar: calendar
        )
        #expect(risks.count == 1)
        #expect(risks[0].severity == .onTrack)
        #expect(risks[0].suggestedStartBy == nil)
        #expect(risks[0].projectedSlackHours > 0)
    }

    @Test("more work than slack → atRisk with suggestedStartBy")
    func atRisk() {
        let analyzer = DeadlineRiskAnalyzer()
        // Today only (deadline 18:00 today) = 9h free, but 20h of competing work.
        let big = TaskItem(title: "overcommit", deadlineAt: at(18, day: 8))
        let risks = analyzer.analyze(
            tasks: [big],
            events: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 20 * 3600),
            horizon: horizon,
            now: at(9),
            calendar: calendar
        )
        #expect(risks.count == 1)
        #expect(risks[0].severity == .atRisk)
        #expect(risks[0].projectedSlackHours < 0)
        // Raw formula (deadline − 20h) lands before `now`; clamped to `now`
        // (= "start now"), never a nonsensical past/overnight instant.
        #expect(risks[0].suggestedStartBy == at(9))
    }

    @Test("competing set sums higher/equal priority tasks with earlier-or-equal deadline")
    func competingSet() {
        let analyzer = DeadlineRiskAnalyzer()
        let deadline = at(18, day: 8)
        // Target: medium priority, deadline today 18:00, 1h.
        let target = TaskItem(title: "target", deadlineAt: deadline, priority: .medium, estimatedDurationSeconds: nil)
        // Competitor: high priority, deadline today 12:00 → counts (>= priority, <= deadline).
        let competitor = TaskItem(title: "comp", deadlineAt: at(12, day: 8), priority: .high)
        // Low priority earlier deadline → excluded (lower priority).
        let lowPrio = TaskItem(title: "low", deadlineAt: at(11, day: 8), priority: .low)
        let risks = analyzer.analyze(
            tasks: [target, competitor, lowPrio],
            events: [],
            prefs: prefs,
            // 4h each → target+competitor = 8h competing for target; lowPrio excluded.
            estimator: FixedEstimator(seconds: 4 * 3600),
            horizon: horizon,
            now: at(9),
            calendar: calendar
        )
        let targetRisk = risks.first { $0.taskID == target.id }
        #expect(targetRisk != nil)
        // 9h free today − 8h competing = ~1h slack → tight (below onTrack 2h, >= 0).
        #expect(targetRisk?.severity == .tight)
    }

    @Test("deterministic output order for identical input")
    func determinism() {
        let analyzer = DeadlineRiskAnalyzer()
        let tasks = [
            TaskItem(title: "a", deadlineAt: at(12, day: 9)),
            TaskItem(title: "b", deadlineAt: at(12, day: 10)),
            TaskItem(title: "c", deadlineAt: at(12, day: 9)),
        ]
        let est = FixedEstimator(seconds: 3600)
        let a = analyzer.analyze(tasks: tasks, events: [], prefs: prefs, estimator: est, horizon: horizon, now: at(9), calendar: calendar)
        let b = analyzer.analyze(tasks: tasks, events: [], prefs: prefs, estimator: est, horizon: horizon, now: at(9), calendar: calendar)
        #expect(a.map(\.taskID) == b.map(\.taskID))
    }

    @Test("done tasks are not analyzed")
    func doneExcluded() {
        let analyzer = DeadlineRiskAnalyzer()
        let done = TaskItem(title: "done", deadlineAt: at(12, day: 9), status: .done)
        let risks = analyzer.analyze(
            tasks: [done],
            events: [],
            prefs: prefs,
            estimator: FixedEstimator(seconds: 3600),
            horizon: horizon,
            now: at(9),
            calendar: calendar
        )
        #expect(risks.isEmpty)
    }
}
