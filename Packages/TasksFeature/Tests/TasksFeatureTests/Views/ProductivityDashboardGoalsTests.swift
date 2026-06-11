import Foundation
import Testing

@testable import TasksFeature

@Suite("ProductivityDashboardView goals copy")
struct ProductivityDashboardGoalsTests {
    private func progress(
        daily: Int = 0,
        weekly: Int = 0,
        dailyTarget: Int = 5,
        weeklyTarget: Int = 25,
        streakAtRisk: Int? = nil
    ) -> ProductivityStatsService.GoalProgress {
        ProductivityStatsService.GoalProgress(
            dailyCompleted: daily,
            weeklyCompleted: weekly,
            dailyTarget: dailyTarget,
            weeklyTarget: weeklyTarget,
            streakAtRisk: streakAtRisk
        )
    }

    @Test func streakProtectionWinsOverRemainingCopy() {
        let copy = ProductivityDashboardView.goalStatusCopy(for: progress(streakAtRisk: 7))
        #expect(copy == "Complete a task today to keep your 7-day streak.")
    }

    @Test func reachedDailyGoalCopy() {
        let copy = ProductivityDashboardView.goalStatusCopy(for: progress(daily: 5))
        #expect(copy == "Daily goal reached — nice work.")
    }

    @Test func remainingCopyHandlesSingularAndPlural() {
        #expect(ProductivityDashboardView.goalStatusCopy(for: progress(daily: 4)) == "1 task to go today.")
        #expect(ProductivityDashboardView.goalStatusCopy(for: progress(daily: 2)) == "3 tasks to go today.")
    }

    @Test func disabledDailyTargetYieldsNoCopy() {
        #expect(ProductivityDashboardView.goalStatusCopy(for: progress(dailyTarget: 0)) == nil)
    }
}
