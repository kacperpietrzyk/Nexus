import Foundation
import NexusCore

/// Wire DTO for `GoalsPreferences` (productivity targets). Maps 1:1; CodingKeys
/// are snake_case to match the `stats.goals.*` tool input schema.
public struct GoalsDTO: Codable, Sendable, Equatable {
    public let dailyCompletionTarget: Int
    public let weeklyCompletionTarget: Int

    public init(from goals: GoalsPreferences) {
        self.dailyCompletionTarget = goals.dailyCompletionTarget
        self.weeklyCompletionTarget = goals.weeklyCompletionTarget
    }

    private enum CodingKeys: String, CodingKey {
        case dailyCompletionTarget = "daily_completion_target"
        case weeklyCompletionTarget = "weekly_completion_target"
    }
}
