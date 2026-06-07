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
    let onSave: (EventDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var title: String
    @State private var calendarID: String
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay: Bool
    @State private var location: String
    @State private var attendees: [String]
    @State private var recurrence: RecurrenceChoice
    @State private var alarmChoice: AlarmChoice

    public init(
        mode: Mode,
        calendars: [CalendarInfo],
        initial: EventDraft? = nil,
        onSave: @escaping (EventDraft) -> Void,
        onDelete: (() -> Void)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.calendars = calendars
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        let writable = calendars.first(where: \.isWritable)
        let base =
            initial
            ?? EventDraft(
                calendarID: writable?.id ?? calendars.first?.id ?? "",
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
        _recurrence = State(initialValue: RecurrenceChoice(rrule: base.recurrence))
        _alarmChoice = State(initialValue: AlarmChoice(offsets: base.alarmOffsets))
    }

    public var body: some View {
        Form {
            Section("Event") {
                TextField("Title", text: $title)
                Picker("Calendar", selection: $calendarID) {
                    ForEach(calendars.filter(\.isWritable)) { calendar in
                        Text(calendar.title).tag(calendar.id)
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
                    ForEach(RecurrenceChoice.allCases) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                Picker("Alert", selection: $alarmChoice) {
                    ForEach(AlarmChoice.allCases) { choice in
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
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || calendarID.isEmpty)
                if case .edit = mode, let onDelete {
                    Button("Delete event", role: .destructive, action: onDelete)
                }
                Button("Cancel", role: .cancel, action: onCancel)
            }
        }
        .formStyle(.grouped)
    }

    private var dateComponents: DatePickerComponents {
        isAllDay ? [.date] : [.date, .hourAndMinute]
    }

    private func save() {
        let draft = EventDraft(
            calendarID: calendarID,
            title: title.trimmingCharacters(in: .whitespaces),
            start: start,
            end: max(end, start),
            isAllDay: isAllDay,
            location: location.isEmpty ? nil : location,
            attendees: attendees,
            recurrence: recurrence.rrule,
            alarmOffsets: alarmChoice.offsets
        )
        onSave(draft)
    }
}

/// Recurrence presets mapped onto the existing `RRule` (spec §9 reuse).
enum RecurrenceChoice: String, CaseIterable, Identifiable, Hashable {
    case none
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    init(rrule: RRule?) {
        guard let rrule else { self = .none; return }
        switch rrule.frequency {
        case .daily: self = .daily
        case .weekly: self = .weekly
        case .monthly: self = .monthly
        }
    }

    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        }
    }

    var rrule: RRule? {
        switch self {
        case .none: return nil
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

    var label: String {
        switch self {
        case .none: return "None"
        case .atTime: return "At time of event"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .oneHour: return "1 hour before"
        }
    }

    var offsets: [TimeInterval] {
        switch self {
        case .none: return []
        case .atTime: return [0]
        case .fiveMinutes: return [-300]
        case .fifteenMinutes: return [-900]
        case .oneHour: return [-3600]
        }
    }
}
