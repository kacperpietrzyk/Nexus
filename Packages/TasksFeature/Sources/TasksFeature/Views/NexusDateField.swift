import NexusUI
import SwiftUI

/// A Linear-styled date field: a control-tile button showing the formatted date
/// (and optional time) that opens a graphical picker in a popover. Replaces the
/// native compact/stepper `DatePicker`, which renders as a systemy text field
/// with up/down steppers that clashes with the dark theme.
struct NexusDateField: View {
    @Binding var date: Date
    var components: DatePickerComponents = [.date]
    /// Inclusive lower bound (e.g. an end date must be after its start).
    var minDate: Date?
    var isEnabled: Bool = true
    let accessibilityLabel: String

    @State private var presented = false

    var body: some View {
        Button {
            presented = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "calendar")
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
        .popover(isPresented: $presented, arrowEdge: .bottom) {
            picker
                .padding(12)
                .frame(width: components.contains(.hourAndMinute) ? 320 : 260)
        }
    }

    @ViewBuilder
    private var picker: some View {
        if let minDate {
            DatePicker("", selection: $date, in: minDate..., displayedComponents: components)
                .datePickerStyle(.graphical)
                .labelsHidden()
        } else {
            DatePicker("", selection: $date, displayedComponents: components)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
    }

    private var formatted: String {
        date.formatted(
            date: .abbreviated,
            time: components.contains(.hourAndMinute) ? .shortened : .omitted
        )
    }
}
