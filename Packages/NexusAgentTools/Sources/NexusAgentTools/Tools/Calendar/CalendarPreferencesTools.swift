import Foundation
import NexusCore

/// `calendar.preferences.get` (spec §4.4): returns the persisted scheduling /
/// calendar preferences (workday window, block sizes, buffer, read/write calendars,
/// rollover, recurring-preview horizon). Read-only.
public struct CalendarPreferencesGetTool: AgentTool {
    public let name = "calendar.preferences.get"
    public let description =
        "Returns the scheduling/calendar preferences (workday window, block sizes, buffer, calendars)."
    public let inputSchema: JSONSchema = .object(properties: [:], required: [])

    private let store: UserDefaultsCalendarPreferencesStore

    public init(store: UserDefaultsCalendarPreferencesStore = .init()) {
        self.store = store
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        try TasksToolJSON.encode(CalendarPreferencesDTO(from: store.load()))
    }
}

/// `calendar.preferences.update` (spec §4.4): partial update. Only fields present in
/// `args` are changed; everything else is preserved. Returns the updated preferences
/// as a `CalendarPreferencesDTO`. Note: optional fields can be set but not cleared to
/// nil through this contract (omitting a field means "leave unchanged").
public struct CalendarPreferencesUpdateTool: AgentTool {
    public let name = "calendar.preferences.update"
    public let description =
        "Updates one or more calendar/scheduling preferences. Only provided fields change."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "workday_start_hour": .integer(minimum: 0, maximum: 23, description: "Workday start hour."),
            "workday_start_minute": .integer(minimum: 0, maximum: 59, description: "Workday start minute."),
            "workday_end_hour": .integer(minimum: 0, maximum: 23, description: "Workday end hour."),
            "workday_end_minute": .integer(minimum: 0, maximum: 59, description: "Workday end minute."),
            "min_block_minutes": .integer(minimum: 1, description: "Minimum schedulable block."),
            "max_block_minutes": .integer(minimum: 1, description: "Maximum schedulable block."),
            "buffer_minutes": .integer(minimum: 0, description: "Buffer between blocks."),
            "read_calendar_ids": .array(items: .string(), description: "Calendar IDs to read."),
            "write_calendar_id": .string(description: "Calendar ID to write blocks to."),
            "rollover_enabled": .boolean(description: "Roll incomplete tasks to the next day."),
            "series_preview_horizon_days": .integer(minimum: 0, description: "Recurring preview horizon."),
        ],
        required: []
    )

    private let store: UserDefaultsCalendarPreferencesStore

    public init(store: UserDefaultsCalendarPreferencesStore = .init()) {
        self.store = store
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        var prefs = store.load()
        if let hour = args["workday_start_hour"]?.intValue { prefs.workdayStart.hour = hour }
        if let minute = args["workday_start_minute"]?.intValue { prefs.workdayStart.minute = minute }
        if let hour = args["workday_end_hour"]?.intValue { prefs.workdayEnd.hour = hour }
        if let minute = args["workday_end_minute"]?.intValue { prefs.workdayEnd.minute = minute }
        if let value = args["min_block_minutes"]?.intValue { prefs.minBlockMinutes = value }
        if let value = args["max_block_minutes"]?.intValue { prefs.maxBlockMinutes = value }
        if let value = args["buffer_minutes"]?.intValue { prefs.bufferMinutes = value }
        if let ids = args["read_calendar_ids"]?.arrayValue {
            prefs.readCalendarIDs = ids.compactMap(\.stringValue)
        }
        if let id = args["write_calendar_id"]?.stringValue { prefs.writeCalendarID = id }
        if let value = args["rollover_enabled"]?.boolValue { prefs.rolloverEnabled = value }
        if let value = args["series_preview_horizon_days"]?.intValue {
            prefs.seriesPreviewHorizonDays = value
        }
        store.save(prefs)
        return try TasksToolJSON.encode(CalendarPreferencesDTO(from: prefs))
    }
}
