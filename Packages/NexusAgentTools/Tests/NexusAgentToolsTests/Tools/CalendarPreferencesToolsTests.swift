import Foundation
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("calendar.preferences")
struct CalendarPreferencesToolsTests {
    private func freshStore() -> UserDefaultsCalendarPreferencesStore {
        let suite = UserDefaults(suiteName: "test.calprefs.\(UUID().uuidString)")!
        return UserDefaultsCalendarPreferencesStore(defaults: suite)
    }

    @Test("update then get round-trips buffer minutes")
    @MainActor
    func roundTrip() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let store = freshStore()
        _ = try await CalendarPreferencesUpdateTool(store: store)
            .call(args: .object(["buffer_minutes": .int(15)]), context: context)
        let out = try await CalendarPreferencesGetTool(store: store)
            .call(args: .object([:]), context: context)
        #expect(out["buffer_minutes"]?.intValue == 15)
    }

    @Test("update flattens workday DateComponents to hour/minute and round-trips them")
    @MainActor
    func workdayDateComponentsRoundTrip() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let store = freshStore()
        _ = try await CalendarPreferencesUpdateTool(store: store).call(
            args: .object([
                "workday_start_hour": .int(7),
                "workday_start_minute": .int(45),
                "workday_end_hour": .int(20),
                "workday_end_minute": .int(30),
            ]),
            context: context
        )
        let out = try await CalendarPreferencesGetTool(store: store)
            .call(args: .object([:]), context: context)
        #expect(out["workday_start_hour"]?.intValue == 7)
        #expect(out["workday_start_minute"]?.intValue == 45)
        #expect(out["workday_end_hour"]?.intValue == 20)
        #expect(out["workday_end_minute"]?.intValue == 30)
    }

    @Test("update stores read_calendar_ids and they round-trip")
    @MainActor
    func readCalendarIDsRoundTrip() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let store = freshStore()
        _ = try await CalendarPreferencesUpdateTool(store: store).call(
            args: .object(["read_calendar_ids": .array([.string("cal-A"), .string("cal-B")])]),
            context: context
        )
        let out = try await CalendarPreferencesGetTool(store: store)
            .call(args: .object([:]), context: context)
        #expect(out["read_calendar_ids"]?.arrayValue?.compactMap(\.stringValue) == ["cal-A", "cal-B"])
    }

    @Test("omitted fields are preserved across a partial update")
    @MainActor
    func partialUpdatePreservesOtherFields() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let store = freshStore()
        _ = try await CalendarPreferencesUpdateTool(store: store)
            .call(args: .object(["buffer_minutes": .int(15)]), context: context)
        _ = try await CalendarPreferencesUpdateTool(store: store)
            .call(args: .object(["rollover_enabled": .bool(false)]), context: context)
        let out = try await CalendarPreferencesGetTool(store: store)
            .call(args: .object([:]), context: context)
        #expect(out["buffer_minutes"]?.intValue == 15)
        #expect(out["rollover_enabled"]?.boolValue == false)
    }
}
