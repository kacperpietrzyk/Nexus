import Foundation

@MainActor
public enum DefaultSchedulesSeed {
    public static let seededKey = "AgentDefaultsSchedulesSeeded.v1"

    public static func runIfNeeded(
        store: AgentScheduleStore,
        defaults: UserDefaults = .standard
    ) throws {
        guard !defaults.bool(forKey: seededKey) else { return }
        var existingIdentities = Set(try store.allActive().map(DefaultScheduleIdentity.init))
        for definition in defaultDefinitions where !existingIdentities.contains(definition.identity) {
            _ = try store.create(
                name: definition.name,
                kind: definition.kind,
                cronExpression: definition.cronExpression,
                prompt: definition.prompt,
                enabled: definition.enabled
            )
            existingIdentities.insert(definition.identity)
        }

        if defaultDefinitions.allSatisfy({ existingIdentities.contains($0.identity) }) {
            defaults.set(true, forKey: seededKey)
        }
    }
}

private struct DefaultScheduleDefinition {
    let name: String
    let kind: AgentScheduleKind
    let cronExpression: String
    let prompt: String
    let enabled: Bool

    var identity: DefaultScheduleIdentity {
        DefaultScheduleIdentity(name: name, kind: kind)
    }
}

private struct DefaultScheduleIdentity: Hashable {
    let name: String
    let kind: AgentScheduleKind

    init(name: String, kind: AgentScheduleKind) {
        self.name = name
        self.kind = kind
    }

    init(schedule: AgentSchedule) {
        self.init(name: schedule.name, kind: schedule.kind)
    }
}

private let defaultDefinitions = [
    DefaultScheduleDefinition(
        name: "Morning Brief",
        kind: .builtIn,
        cronExpression: "0 8 * * *",
        prompt: """
            Build today's brief: tasks due today (priority + deadline),
            calendar events, open PRs waiting on me,
            suggestions for where to start. Save as a card in Today + send a notification.
            """,
        enabled: true
    ),
    DefaultScheduleDefinition(
        name: "Evening Plan",
        kind: .builtIn,
        cronExpression: "0 18 * * *",
        prompt: """
            Summarise the day: what's done, what to reschedule, what's stuck.
            Propose the 3 most important things for tomorrow (with reasoning).
            """,
        enabled: true
    ),
    DefaultScheduleDefinition(
        name: "Weekly Review",
        kind: .builtIn,
        cronExpression: "0 18 * * 0",
        prompt: """
            Per-project weekly review: progress vs last week,
            stuck items, action items for the coming week.
            """,
        enabled: true
    ),
    DefaultScheduleDefinition(
        name: "Project Digest",
        kind: .projectDigest,
        cronExpression: "0 9 * * 1",
        prompt: "Custom digest — user defines per-project in the project UI.",
        enabled: false
    ),
]
