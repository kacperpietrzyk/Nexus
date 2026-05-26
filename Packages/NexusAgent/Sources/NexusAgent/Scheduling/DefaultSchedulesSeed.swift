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
            Zbuduj brief dnia: dzisiejsze taski (priority + deadline),
            eventy w kalendarzu, otwarte PR-y czekające na mnie,
            sugestie 'na czym zacząć'. Zapisz jako card w Today + notyfikacja.
            """,
        enabled: true
    ),
    DefaultScheduleDefinition(
        name: "Evening Plan",
        kind: .builtIn,
        cronExpression: "0 18 * * *",
        prompt: """
            Podsumuj dzień: co skończone, co przesunąć, co utknęło.
            Zaproponuj 3 najważniejsze rzeczy na jutro (z uzasadnieniem).
            """,
        enabled: true
    ),
    DefaultScheduleDefinition(
        name: "Weekly Review",
        kind: .builtIn,
        cronExpression: "0 18 * * 0",
        prompt: """
            Per-projekt review tygodnia: progress vs poprzedni tydzień,
            stuck items, action items na nadchodzący tydzień.
            """,
        enabled: true
    ),
    DefaultScheduleDefinition(
        name: "Project Digest",
        kind: .projectDigest,
        cronExpression: "0 9 * * 1",
        prompt: "Custom digest — user definiuje per-projekt w UI projektu.",
        enabled: false
    ),
]
