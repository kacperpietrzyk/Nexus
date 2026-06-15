import SwiftUI

// MARK: - NexusDateField

/// The canonical themed date/time field — a control-tile button showing the
/// formatted date (and optional time) that opens a graphical picker in a
/// popover. Replaces the native compact/stepper `DatePicker`, whose systemy text
/// field + up/down steppers clash with the Liquid palette.
///
/// Shares the exact control-tile idiom as `NexusSelect`/`NexusTextField`
/// (`Background.control` fill, hairline border, `r1`, `bodySmall`). Promoted from
/// TasksFeature into the design system so every module (Calendar, Settings, …)
/// reuses one date control instead of re-rolling native `DatePicker`s.
///
/// Usage:
/// ```swift
/// NexusDateField(date: $due, components: [.date], accessibilityLabel: "Due date")
/// NexusDateField(date: $start, components: [.date, .hourAndMinute], accessibilityLabel: "Start")
/// ```
public struct NexusDateField: View {
    @Binding public var date: Date
    public var components: DatePickerComponents
    /// Inclusive lower bound (e.g. an end date must be after its start).
    public var minDate: Date?
    public var isEnabled: Bool
    public let accessibilityLabel: String

    public init(
        date: Binding<Date>,
        components: DatePickerComponents = [.date],
        minDate: Date? = nil,
        isEnabled: Bool = true,
        accessibilityLabel: String
    ) {
        self._date = date
        self.components = components
        self.minDate = minDate
        self.isEnabled = isEnabled
        self.accessibilityLabel = accessibilityLabel
    }

    @State private var presented = false

    public var body: some View {
        Button {
            presented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: components.contains(.hourAndMinute) && !components.contains(.date) ? "clock" : "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(NexusColor.Text.tertiary)
                Text(formatted)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(isEnabled ? NexusColor.Text.primary : NexusColor.Text.disabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                NexusColor.Background.control,
                in: RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(formatted)
        // `popover` is unavailable on watchOS; fall back to a sheet there.
        #if os(watchOS)
        .sheet(isPresented: $presented) {
            picker.padding(12)
        }
        #else
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            picker
                .padding(12)
                .frame(width: components.contains(.hourAndMinute) ? 320 : 260)
        }
        #endif
    }

    @ViewBuilder
    private var picker: some View {
        // `.graphical` is unavailable on watchOS; fall back to the default style.
        #if os(watchOS)
        rawPicker
        #else
        rawPicker.datePickerStyle(.graphical)
        #endif
    }

    @ViewBuilder
    private var rawPicker: some View {
        if let minDate {
            DatePicker("", selection: $date, in: minDate..., displayedComponents: components)
                .labelsHidden()
        } else {
            DatePicker("", selection: $date, displayedComponents: components)
                .labelsHidden()
        }
    }

    private var formatted: String {
        if components.contains(.hourAndMinute) && !components.contains(.date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(
            date: .abbreviated,
            time: components.contains(.hourAndMinute) ? .shortened : .omitted
        )
    }
}
