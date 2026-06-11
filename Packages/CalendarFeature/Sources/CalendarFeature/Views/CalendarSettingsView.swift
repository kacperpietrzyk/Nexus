import NexusCore
import NexusUI
import SwiftUI

/// Multi-calendar Settings (spec §9 / §13): pick which calendars are read as busy
/// obstacles, choose / create the "Nexus" write-target, and tune the working window
/// + block sizing. Writes to `CalendarPreferences` via the view-model.
public struct CalendarSettingsView: View {
    @Bindable var viewModel: CalendarViewModel

    @State private var calendars: [CalendarInfo] = []
    @State private var prefs: CalendarPreferences = .default
    @State private var workdayStart = Date()
    @State private var workdayEnd = Date()
    @State private var loaded = false

    public init(viewModel: CalendarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            if !viewModel.hasCalendarAccess {
                Section {
                    Button("Grant calendar access") {
                        Task { await viewModel.requestAccess() }
                    }
                }
            }

            Section("Read calendars (busy obstacles)") {
                if calendars.isEmpty {
                    Text("No calendars available.")
                        .font(NexusType.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                }
                ForEach(calendars) { calendar in
                    Toggle(isOn: readBinding(for: calendar.id)) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(calendar.colorHex.flatMap { Color(calendarHex: $0) } ?? NexusColor.Text.tertiary)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(calendar.title).font(NexusType.bodySmall)
                                Text(calendar.sourceTitle)
                                    .font(NexusType.caption)
                                    .foregroundStyle(NexusColor.Text.muted)
                            }
                        }
                    }
                }
            }

            Section("Nexus write calendar") {
                Picker("Write target", selection: writeTargetBinding) {
                    Text("None").tag(String?.none)
                    ForEach(calendars.filter(\.isWritable)) { calendar in
                        Text(calendar.title).tag(Optional(calendar.id))
                    }
                }
                Button("Create / ensure \"Nexus\" calendar") {
                    Task { await ensureNexusCalendar() }
                }
            }

            Section("Working window") {
                DatePicker("Day starts", selection: $workdayStart, displayedComponents: .hourAndMinute)
                DatePicker("Day ends", selection: $workdayEnd, displayedComponents: .hourAndMinute)
                Stepper("Min block: \(prefs.minBlockMinutes) min", value: $prefs.minBlockMinutes, in: 5...60, step: 5)
                Stepper("Max block: \(prefs.maxBlockMinutes) min", value: $prefs.maxBlockMinutes, in: 30...240, step: 15)
                Stepper("Buffer: \(prefs.bufferMinutes) min", value: $prefs.bufferMinutes, in: 0...60, step: 5)
                Toggle("Auto-rollover unfinished tasks", isOn: $prefs.rolloverEnabled)
            }

            Section("Recurring series") {
                Stepper(
                    "Preview horizon: \(prefs.seriesPreviewHorizonDays) days",
                    value: $prefs.seriesPreviewHorizonDays,
                    in: 0...30
                )
                Text("Show ghost blocks for upcoming occurrences of recurring tasks this many days ahead. 0 turns previews off.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }

            Section {
                Button("Save", action: persist)
            }
        }
        .formStyle(.grouped)
        .task {
            guard !loaded else { return }
            loaded = true
            prefs = viewModel.preferences
            calendars = await viewModel.availableCalendars()
            syncWorkdayDates()
        }
    }

    private func readBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { prefs.readCalendarIDs.isEmpty || prefs.readCalendarIDs.contains(id) },
            set: { isOn in
                var ids = effectiveReadIDs()
                if isOn { ids.insert(id) } else { ids.remove(id) }
                prefs.readCalendarIDs = Array(ids).sorted()
            }
        )
    }

    private var writeTargetBinding: Binding<String?> {
        Binding(get: { prefs.writeCalendarID }, set: { prefs.writeCalendarID = $0 })
    }

    /// Materialize the implicit "empty == all granted" set into explicit IDs so a
    /// toggle-off has something to remove from.
    private func effectiveReadIDs() -> Set<String> {
        if prefs.readCalendarIDs.isEmpty {
            return Set(calendars.map(\.id))
        }
        return Set(prefs.readCalendarIDs)
    }

    private func ensureNexusCalendar() async {
        // Routing through the view-model's writer keeps EventKit isolated; the
        // returned id becomes the write target.
        await viewModel.requestAccess()
        calendars = await viewModel.availableCalendars()
    }

    private func syncWorkdayDates() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        workdayStart = calendar.date(byAdding: prefs.workdayStart, to: today) ?? today
        workdayEnd = calendar.date(byAdding: prefs.workdayEnd, to: today) ?? today
    }

    private func persist() {
        let calendar = Calendar.current
        prefs.workdayStart = calendar.dateComponents([.hour, .minute], from: workdayStart)
        prefs.workdayEnd = calendar.dateComponents([.hour, .minute], from: workdayEnd)
        viewModel.savePreferences(prefs)
    }
}
