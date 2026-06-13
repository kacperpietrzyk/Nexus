import Foundation
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("stats tools")
struct StatsToolsTests {
    @Test("goals update then get round-trips and preserves untouched field")
    @MainActor
    func goals() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let suiteName = "test.goals.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsGoalsPreferencesStore(defaults: defaults)
        _ = try await StatsGoalsUpdateTool(store: store).call(
            args: .object(["daily_completion_target": .int(7)]),
            context: context
        )
        let out = try await StatsGoalsGetTool(store: store).call(args: .object([:]), context: context)
        // Non-default daily proves the write path; weekly stays at the 25 default,
        // proving the partial update leaves untouched fields alone.
        #expect(out["daily_completion_target"]?.intValue == 7)
        #expect(out["weekly_completion_target"]?.intValue == 25)
    }

    @Test("productivity counts completed tasks in range")
    @MainActor
    func productivity() async throws {
        let task = TaskItem(title: "Done")
        task.lastCompletedAt = Date(timeIntervalSince1970: 1_700_000_500)
        let (context, container, _) = try await InMemoryAgentContext.make(tasks: [task])
        _ = container
        let out = try await StatsProductivityTool().call(
            args: .object([
                "from": .string("2023-11-14T00:00:00Z"),
                "to": .string("2023-11-15T00:00:00Z"),
            ]),
            context: context
        )
        #expect(out["completed_count"]?.intValue == 1)
        // Echoed range is normalized through ScheduleDTOFormatter (stable,
        // no-fractional ISO8601) — guards key naming and formatter regressions.
        #expect(out["from"]?.stringValue == "2023-11-14T00:00:00Z")
        #expect(out["to"]?.stringValue == "2023-11-15T00:00:00Z")
    }
}
