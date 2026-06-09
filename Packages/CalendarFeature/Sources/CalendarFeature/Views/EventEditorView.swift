import NexusCore
import NexusUI
import SwiftUI

/// Native event editor (spec §9): title, time / all-day, location, attendees
/// (read-only on write — EventKit limitation), RRule recurrence, alarms, and the
/// target calendar. Backed by the provider CRUD via the view-model.
///
/// Attendees note: `EKEvent.attendees` is read-only in EventKit's public API, so the
/// editor surfaces existing attendees but cannot add them on write (mirrors
/// `EventDraft` / `EventKitCalendarProvider+Writing`).
public struct EventEditorView: View {
    public enum Mode: Equatable {
        case create
        case edit(eventID: String)
    }

    let mode: Mode
    let calendars: [CalendarInfo]
    let onSave: (EventDraft, CalendarEventSpan) -> Void
    let onDelete: ((CalendarEventSpan) -> Void)?
    let onCancel: () -> Void

    @State private var title: String
    /// `nil` ⇒ the "None" tag: no system-calendar event is written (#7).
    @State private var calendarID: String?
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var attendees: [String]
    @State private var recurrence: RecurrenceChoice
    @State private var alarmChoice: AlarmChoice
    /// Drives the span confirmation dialog for a recurring event (R2/R3): a Save
    /// or Delete on an event that already recurs must ask whether it applies to
    /// this occurrence only or this-and-future, mirroring Apple Calendar.
    @State private var spanPrompt: SpanPrompt?

    private enum SpanPrompt: Identifiable {
        case save
        case delete
        var id: Int { self == .save ? 0 : 1 }
    }

    /// Original rich values carried verbatim through the lossy preset pickers.
    /// When the matching choice is `.custom` (the preset round-trip would lose
    /// data — a rich `RRule` or a multi/10-min alarm), `save()` re-emits these
    /// untouched instead of the flattened preset (F2/F3).
    private let originalRecurrence: RRule?
    private let originalAlarmOffsets: [TimeInterval]

    public init(
        mode: Mode,
        calendars: [CalendarInfo],
        initial: EventDraft? = nil,
        preferredCalendarID: String? = nil,
        onSave: @escaping (EventDraft, CalendarEventSpan) -> Void,
        onDelete: ((CalendarEventSpan) -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.calendars = calendars
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        // #7 create default: seed from the user's configured write target (falling
        // back to the first writable calendar) instead of always grabbing the first
        // writable one. An edit passes its own `initial`, so this only steers create.
        let writable = calendars.first(where: \.isWritable)
        let seededCalendarID =
            preferredCalendarID.flatMap { id in calendars.first { $0.id == id }?.id }
            ?? writable?.id
            ?? calendars.first?.id
        let base =
            initial
            ?? EventDraft(
                calendarID: seededCalendarID,
                title: "",
                start: Date(),
                end: Date().addingTimeInterval(3600)
            )
        _title = State(initialValue: base.title)
        _calendarID = State(initialValue: base.calendarID)
        _start = State(initialValue: base.start)
        _end = State(initialValue: base.end)
        _isAllDay = State(initialValue: base.isAllDay)
        _location = State(initialValue: base.location ?? "")
        _attendees = State(initialValue: base.attendees)
        _recurrence = State(initialValue: RecurrenceChoice.forOriginal(base.recurrence))
        _alarmChoice = State(initialValue: AlarmChoice.forOriginal(base.alarmOffsets))
        originalRecurrence = base.recurrence
        originalAlarmOffsets = base.alarmOffsets
    }

    public var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                Picker("Calendar", selection: $calendarID) {
                    // #7: "None" writes no system-calendar event; mirrors the
                    // Settings "Write target" picker.
                    Text("None").tag(String?.none)
                    ForEach(calendars.filter(\.isWritable)) { calendar in
                        Text(calendar.title).tag(Optional(calendar.id))
                    }
                }
            }

            Section("Time") {
                Toggle("All-day", isOn: $isAllDay)
                DatePicker("Starts", selection: $start, displayedComponents: dateComponents)
                DatePicker("Ends", selection: $end, displayedComponents: dateComponents)
            }

            Section("Details") {
                TextField("Location", text: $location)
                Picker("Repeat", selection: $recurrence) {
                    ForEach(recurrenceOptions) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                Picker("Alert", selection: $alarmChoice) {
                    ForEach(alarmOptions) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
            }

            if !attendees.isEmpty {
                Section("Attendees") {
                    ForEach(attendees, id: \.self) { attendee in
                        Text(attendee)
                            .font(NexusType.bodySmall)
                            .foregroundStyle(NexusColor.Text.secondary)
                    }
                    Text("Attendees are read-only (EventKit limitation).")
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.muted)
                }
            }

            Section {
                Button("Save", action: save)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                if case .edit = mode, onDelete != nil {
                    Button("Delete event", role: .destructive, action: requestDelete)
                }
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            spanPrompt == .delete ? "Delete recurring event" : "Save recurring event",
            isPresented: spanPromptBinding,
            titleVisibility: .visible,
            presenting: spanPrompt
        ) { prompt in
            spanDialogButtons(for: prompt)
        }
    }

    @ViewBuilder
    private func spanDialogButtons(for prompt: SpanPrompt) -> some View {
        switch prompt {
        case .save:
            Button("Save This Event") { commit(prompt, span: .thisEvent) }
            Button("Save Future Events") { commit(prompt, span: .futureEvents) }
        case .delete:
            Button("Delete This Event", role: .destructive) { commit(prompt, span: .thisEvent) }
            Button("Delete Future Events", role: .destructive) { commit(prompt, span: .futureEvents) }
        }
        Button("Cancel", role: .cancel) { spanPrompt = nil }
    }

    private var spanPromptBinding: Binding<Bool> {
        Binding(get: { spanPrompt != nil }, set: { if !$0 { spanPrompt = nil } })
    }

    private var dateComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    /// `.custom` is offered only when the original recurrence can't be represented
    /// by a preset; otherwise selecting it would have no original to restore.
    private var recurrenceOptions: [RecurrenceChoice] {
        RecurrenceChoice.presets + (RecurrenceChoice.forOriginal(originalRecurrence) == .custom ? [.custom] : [])
    }

    private var alarmOptions: [AlarmChoice] {
        AlarmChoice.presets + (AlarmChoice.forOriginal(originalAlarmOffsets) == .custom ? [.custom] : [])
    }

    /// Whether the event being edited already recurs — only then does an EventKit
    /// span apply, so only then do we ask the user (R2/R3).
    private var editsRecurringEvent: Bool {
        if case .edit = mode { return originalRecurrence != nil }
        return false
    }

    private func makeDraft() -> EventDraft {
        EventDraft(
            calendarID: calendarID,
            title: title.trimmingCharacters(in: .whitespaces),
            start: start,
            end: max(end, start),
            isAllDay: isAllDay,
            location: location.isEmpty ? nil : location,
            attendees: attendees,
            recurrence: Self.resolvedRecurrence(choice: recurrence, original: originalRecurrence),
            alarmOffsets: Self.resolvedAlarms(choice: alarmChoice, original: originalAlarmOffsets)
        )
    }

    private func save() {
        if editsRecurringEvent {
            spanPrompt = .save
        } else {
            onSave(makeDraft(), .thisEvent)
        }
    }

    private func requestDelete() {
        if editsRecurringEvent {
            spanPrompt = .delete
        } else {
            onDelete?(.thisEvent)
        }
    }

    private func commit(_ prompt: SpanPrompt, span: CalendarEventSpan) {
        spanPrompt = nil
        switch prompt {
        case .save: onSave(makeDraft(), span)
        case .delete: onDelete?(span)
        }
    }

    /// F2/F3 merge: a `.custom` choice re-emits the original rich `RRule`
    /// verbatim (the presets can't represent it); any preset overwrites it.
    /// Extracted so the preserve-vs-overwrite contract is unit-testable without
    /// SwiftUI `@State`.
    nonisolated static func resolvedRecurrence(choice: RecurrenceChoice, original: RRule?) -> RRule? {
        choice == .custom ? original : choice.rrule
    }

    /// F2/F3 merge: a `.custom` choice re-emits the original alarm offsets
    /// verbatim (multiple alarms / non-preset offsets); any preset overwrites.
    nonisolated static func resolvedAlarms(choice: AlarmChoice, original: [TimeInterval]) -> [TimeInterval] {
        choice == .custom ? original : choice.offsets
    }
}

/// Recurrence presets mapped onto the existing `RRule` (spec §9 reuse).
enum RecurrenceChoice: String, CaseIterable, Identifiable, Hashable {
    case none
    case daily
    case weekly
    case monthly
    /// Original recurrence the presets can't represent (e.g. `interval:2`,
    /// `byWeekday`, `until`). Carried through `resolvedDraft` untouched.
    case custom

    /// Selectable presets, in display order. `.custom` is appended by the view
    /// only when the original recurrence is genuinely unrepresentable.
    static let presets: [RecurrenceChoice] = [.none, .daily, .weekly, .monthly]

    var id: String { rawValue }

    init(rrule: RRule?) {
        guard let rrule else { self = .none; return }
        switch rrule.frequency {
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        }
    }

    /// The choice to seed the picker with: a preset if it round-trips the rule
    /// losslessly, otherwise `.custom`.
    static func forOriginal(_ rrule: RRule?) -> RecurrenceChoice {
        let preset = RecurrenceChoice(rrule: rrule)
        return preset.rrule == rrule ? preset : .custom
    }

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .custom: return "Custom (keep current)"
        }
    }

    /// Non-nil only for presets. `.custom` is resolved against the original value
    /// in `resolvedDraft`, never via this accessor.
    var rrule: RRule? {
        switch self {
        case .none, .custom: return nil
        case .daily: return RRule(frequency: .daily)
        case .weekly: return RRule(frequency: .weekly)
        case .monthly: return RRule(frequency: .monthly)
        }
    }
}

/// Alarm presets mapped onto `EventDraft.alarmOffsets` (seconds before start).
enum AlarmChoice: String, CaseIterable, Identifiable, Hashable {
    case none
    case atTime
    case fiveMinutes
    case fifteenMinutes
    case oneHour
    /// Original alarm set the presets can't represent (multiple alarms, or a
    /// non-preset offset like 10 minutes). Carried through `resolvedDraft`.
    case custom

    /// Selectable presets, in display order. `.custom` is appended by the view
    /// only when the original alarms are genuinely unrepresentable.
    static let presets: [AlarmChoice] = [.none, .atTime, .fiveMinutes, .fifteenMinutes, .oneHour]

    var id: String { rawValue }

    init(offsets: [TimeInterval]) {
        guard let first = offsets.first else { self = .none; return }
        switch first {
        case 0: self = .atTime
        case -300: self = .fiveMinutes
        case -900: self = .fifteenMinutes
        case -3600: self = .oneHour
        default: self = .none
        }
    }

    /// The choice to seed the picker with: a preset if it round-trips the alarm
    /// set losslessly, otherwise `.custom`.
    static func forOriginal(_ offsets: [TimeInterval]) -> AlarmChoice {
        let preset = AlarmChoice(offsets: offsets)
        return preset.offsets == offsets ? preset : .custom
    }

    var label: String {
        switch self {
        case .none: return "None"
        case .atTime: return "At time of event"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .oneHour: return "1 hour before"
        case .custom: return "Custom (keep current)"
        }
    }

    /// Defined only for presets. `.custom` is resolved against the original value
    /// in `resolvedDraft`, never via this accessor.
    var offsets: [TimeInterval] {
        switch self {
        case .none, .custom: return []
        case .atTime: return [0]
        case .fiveMinutes: return [-300]
        case .fifteenMinutes: return [-900]
        case .oneHour: return [-3600]
        }
    }
}
