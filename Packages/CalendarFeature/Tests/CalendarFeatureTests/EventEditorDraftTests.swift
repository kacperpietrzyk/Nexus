import Foundation
import NexusCore
import Testing

@testable import CalendarFeature

/// F2/F3 regression: the event editor must not flatten rich alarms / recurrence
/// when the user edits an unrelated field. The lossy preset pickers map a rich
/// `RRule` (or a multi/10-min alarm) onto `.custom`, and the resolver carries the
/// original through untouched until the user actively picks a preset.
@Suite("EventEditor draft resolution")
struct EventEditorDraftTests {
    private let until = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Rich recurrence + multi-offset alarm map to .custom and survive")
    func preservesRichValues() {
        let rich = RRule(
            frequency: .weekly,
            interval: 2,
            byWeekday: [.monday, .wednesday],
            until: until
        )
        let alarms: [TimeInterval] = [-600, -3600]

        #expect(RecurrenceChoice.forOriginal(rich) == .custom)
        #expect(AlarmChoice.forOriginal(alarms) == .custom)
        // Editing an unrelated field leaves the choice on .custom → original kept.
        #expect(EventEditorView.resolvedRecurrence(choice: .custom, original: rich) == rich)
        #expect(EventEditorView.resolvedAlarms(choice: .custom, original: alarms) == alarms)
    }

    @Test("User can override a retained-custom value with a preset")
    func overridesCustomWithPreset() {
        let rich = RRule(frequency: .weekly, interval: 2)
        #expect(EventEditorView.resolvedRecurrence(choice: .daily, original: rich) == RRule(frequency: .daily))
        #expect(EventEditorView.resolvedAlarms(choice: .none, original: [-600]) == [])
    }

    @Test("Representable presets round-trip without a custom entry")
    func representablePresetsRoundTrip() {
        let weekly = RRule(frequency: .weekly)
        #expect(RecurrenceChoice.forOriginal(weekly) == .weekly)
        #expect(AlarmChoice.forOriginal([-300]) == .fiveMinutes)
        #expect(RecurrenceChoice.forOriginal(nil) == .none)
        #expect(AlarmChoice.forOriginal([]) == .none)

        #expect(EventEditorView.resolvedRecurrence(choice: .weekly, original: weekly) == weekly)
        #expect(EventEditorView.resolvedAlarms(choice: .fiveMinutes, original: [-300]) == [-300])
    }
}
