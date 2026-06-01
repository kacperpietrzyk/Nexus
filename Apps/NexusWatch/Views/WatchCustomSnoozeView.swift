import Foundation
import NexusUI
import Observation
import SwiftUI

/// Quick-snooze presets shown above the Digital Crown DatePicker on the Watch
/// custom snooze sheet.
enum WatchCustomSnoozeChip: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case fourHours = "4h"
    case tomorrow = "Tomorrow"

    var id: String { rawValue }
}

/// State driver for `WatchCustomSnoozeView`. Holds the currently selected
/// snooze target and applies quick-chip presets relative to an injectable
/// `now` closure so tests can pin time.
@MainActor
@Observable
final class WatchCustomSnoozeViewState {
    var selectedUntil: Date
    private let nowProvider: () -> Date

    init(now: @escaping () -> Date = { Date() }) {
        self.nowProvider = now
        self.selectedUntil = now().addingTimeInterval(3_600)
    }

    func applyQuickChip(_ chip: WatchCustomSnoozeChip) {
        let now = nowProvider()
        switch chip {
        case .oneHour:
            selectedUntil = now.addingTimeInterval(3_600)
        case .fourHours:
            selectedUntil = now.addingTimeInterval(4 * 3_600)
        case .tomorrow:
            let cal = Calendar.current
            let day = cal.startOfDay(for: now)
            let tomorrow = cal.date(byAdding: .day, value: 1, to: day) ?? day
            selectedUntil =
                cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}

/// Sheet presented after the user taps "Choose…" on a Watch task notification.
/// Three quick chips seed `selectedUntil`; the Digital Crown DatePicker can
/// then refine the time.
struct WatchCustomSnoozeView: View {
    @State private var state = WatchCustomSnoozeViewState()
    let taskID: UUID
    let onCommit: (Date) -> Void
    let onCancel: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    ForEach(WatchCustomSnoozeChip.allCases) { chip in
                        Button(chip.rawValue) {
                            state.applyQuickChip(chip)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                DatePicker(
                    "Snooze until",
                    selection: $state.selectedUntil,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                // Lime: single primary action on this surface (confirm snooze).
                // limeInk foreground for contrast on lime fill.
                Button {
                    onCommit(state.selectedUntil)
                } label: {
                    Text("Snooze")
                        .foregroundStyle(NexusColor.Accent.limeInk)
                }
                .buttonStyle(.borderedProminent)
                .tint(NexusColor.Accent.lime)
                Button("Cancel", role: .cancel) { onCancel() }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}
