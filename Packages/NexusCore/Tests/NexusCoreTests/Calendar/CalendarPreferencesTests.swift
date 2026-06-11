import Foundation
import Testing

@testable import NexusCore

private func makeIsolatedDefaults() -> UserDefaults {
    let suite = "test.calendar.preferences.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func calendarPreferences_defaultsMatchSpec() {
    let prefs = CalendarPreferences.default
    #expect(prefs.workdayStart == DateComponents(hour: 9, minute: 0))
    #expect(prefs.workdayEnd == DateComponents(hour: 18, minute: 0))
    #expect(prefs.minBlockMinutes == 15)
    #expect(prefs.maxBlockMinutes == 120)
    #expect(prefs.bufferMinutes == 0)
    #expect(prefs.readCalendarIDs == [])
    #expect(prefs.writeCalendarID == nil)
    #expect(prefs.rolloverEnabled == true)
}

@Test func calendarPreferencesStore_unsetReturnsDefaults() {
    let store = UserDefaultsCalendarPreferencesStore(defaults: makeIsolatedDefaults())
    #expect(store.load() == CalendarPreferences.default)
}

@Test func calendarPreferencesStore_saveLoadRoundTrips() {
    let store = UserDefaultsCalendarPreferencesStore(defaults: makeIsolatedDefaults())
    var prefs = CalendarPreferences.default
    prefs.workdayStart = DateComponents(hour: 8, minute: 30)
    prefs.workdayEnd = DateComponents(hour: 17, minute: 15)
    prefs.minBlockMinutes = 20
    prefs.maxBlockMinutes = 90
    prefs.bufferMinutes = 10
    prefs.readCalendarIDs = ["cal-A", "cal-B"]
    prefs.writeCalendarID = "nexus-cal"
    prefs.rolloverEnabled = false

    store.save(prefs)
    let loaded = store.load()
    #expect(loaded == prefs)
}

@Test func calendarPreferencesStore_overwritePersistsLatest() {
    let store = UserDefaultsCalendarPreferencesStore(defaults: makeIsolatedDefaults())
    store.save(CalendarPreferences(minBlockMinutes: 5))
    store.save(CalendarPreferences(minBlockMinutes: 45))
    #expect(store.load().minBlockMinutes == 45)
}

// MARK: - visibleEvents calendar filter (#6)

private func makeEvent(id: String, calendarID: String?) -> CalendarEvent {
    let start = Date(timeIntervalSince1970: 1_000)
    return CalendarEvent(
        id: id,
        title: id,
        start: start,
        end: start.addingTimeInterval(3_600),
        calendarID: calendarID
    )
}

@Test func calendarPreferences_visibleEvents_emptyReadSetKeepsEverything() {
    let prefs = CalendarPreferences(readCalendarIDs: [])
    let events = [makeEvent(id: "a", calendarID: "work"), makeEvent(id: "b", calendarID: "home")]
    #expect(prefs.visibleEvents(events).map(\.id) == ["a", "b"])
}

@Test func calendarPreferences_visibleEvents_filtersToReadSet() {
    let prefs = CalendarPreferences(readCalendarIDs: ["work"])
    let events = [makeEvent(id: "a", calendarID: "work"), makeEvent(id: "b", calendarID: "home")]
    #expect(prefs.visibleEvents(events).map(\.id) == ["a"])
}

@Test func calendarPreferences_visibleEvents_keepsUnknownCalendarWhenFilterActive() {
    let prefs = CalendarPreferences(readCalendarIDs: ["work"])
    let events = [makeEvent(id: "a", calendarID: "home"), makeEvent(id: "b", calendarID: nil)]
    // The disabled "home" event is hidden; the nil-calendar event is kept (cannot classify).
    #expect(prefs.visibleEvents(events).map(\.id) == ["b"])
}

// MARK: - seriesPreviewHorizonDays (M2)

@Test func calendarPreferences_defaultHorizonIsSevenDays() {
    #expect(CalendarPreferences.default.seriesPreviewHorizonDays == 7)
}

@Test func calendarPreferences_horizonRoundTripsThroughTheStore() {
    let store = UserDefaultsCalendarPreferencesStore(defaults: makeIsolatedDefaults())
    var prefs = CalendarPreferences.default
    prefs.seriesPreviewHorizonDays = 14
    store.save(prefs)
    #expect(store.load().seriesPreviewHorizonDays == 14)
}

@Test func calendarPreferences_legacyPayloadWithoutHorizonDecodesWithDefault() throws {
    // A pre-M2 blob exactly as `UserDefaultsCalendarPreferencesStore` persisted
    // it (no `seriesPreviewHorizonDays` key). Decoding must NOT throw — a throw
    // would make `load()` silently reset the user's preferences to `.default`.
    let legacyJSON = """
        {"workdayStart":{"hour":8,"minute":30},"workdayEnd":{"hour":17,"minute":0},\
        "minBlockMinutes":20,"maxBlockMinutes":90,"bufferMinutes":10,\
        "readCalendarIDs":["cal-A"],"writeCalendarID":"nexus-cal","rolloverEnabled":false}
        """
    let decoded = try JSONDecoder().decode(CalendarPreferences.self, from: Data(legacyJSON.utf8))
    #expect(decoded.seriesPreviewHorizonDays == 7)
    #expect(decoded.workdayStart == DateComponents(hour: 8, minute: 30))
    #expect(decoded.minBlockMinutes == 20)
    #expect(decoded.readCalendarIDs == ["cal-A"])
    #expect(decoded.writeCalendarID == "nexus-cal")
    #expect(decoded.rolloverEnabled == false)
}
