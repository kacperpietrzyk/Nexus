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
