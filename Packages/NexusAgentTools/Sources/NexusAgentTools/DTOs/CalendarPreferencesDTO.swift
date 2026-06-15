import Foundation
import NexusCore

/// Wire DTO for `CalendarPreferences` (spec §4.4). The `workdayStart` / `workdayEnd`
/// `DateComponents` are flattened to hour/minute integers for the JSON contract;
/// everything else maps 1:1. CodingKeys are snake_case to match the tool input schema.
public struct CalendarPreferencesDTO: Codable, Sendable, Equatable {
    public let workdayStartHour: Int
    public let workdayStartMinute: Int
    public let workdayEndHour: Int
    public let workdayEndMinute: Int
    public let minBlockMinutes: Int
    public let maxBlockMinutes: Int
    public let bufferMinutes: Int
    public let readCalendarIDs: [String]
    public let writeCalendarID: String?
    public let rolloverEnabled: Bool
    public let seriesPreviewHorizonDays: Int

    public init(from preferences: CalendarPreferences) {
        self.workdayStartHour = preferences.workdayStart.hour ?? 0
        self.workdayStartMinute = preferences.workdayStart.minute ?? 0
        self.workdayEndHour = preferences.workdayEnd.hour ?? 0
        self.workdayEndMinute = preferences.workdayEnd.minute ?? 0
        self.minBlockMinutes = preferences.minBlockMinutes
        self.maxBlockMinutes = preferences.maxBlockMinutes
        self.bufferMinutes = preferences.bufferMinutes
        self.readCalendarIDs = preferences.readCalendarIDs
        self.writeCalendarID = preferences.writeCalendarID
        self.rolloverEnabled = preferences.rolloverEnabled
        self.seriesPreviewHorizonDays = preferences.seriesPreviewHorizonDays
    }

    private enum CodingKeys: String, CodingKey {
        case workdayStartHour = "workday_start_hour"
        case workdayStartMinute = "workday_start_minute"
        case workdayEndHour = "workday_end_hour"
        case workdayEndMinute = "workday_end_minute"
        case minBlockMinutes = "min_block_minutes"
        case maxBlockMinutes = "max_block_minutes"
        case bufferMinutes = "buffer_minutes"
        case readCalendarIDs = "read_calendar_ids"
        case writeCalendarID = "write_calendar_id"
        case rolloverEnabled = "rollover_enabled"
        case seriesPreviewHorizonDays = "series_preview_horizon_days"
    }
}
