import NexusCore
import NexusUI
import SwiftUI

// Duration-estimate control for `TaskDetailInspector`, split out of the main file
// to keep it under the file/type-length budget. `estimatedDurationSeconds` is a
// user-owned field (Calendar / Motion-AI module, spec §4.2) edited here in
// minutes; the model stores the canonical seconds value with an explicit source.
extension TaskDetailInspector {

    /// Labelled minutes input bound to `estimatedDurationSeconds`. Commits on
    /// submit; an empty/zero/invalid entry clears the estimate. Styled to match
    /// the inspector's existing control idiom (raw `TextField` over a
    /// `Background.control` tile — the custom-RRULE field precedent).
    var estimateRow: some View {
        dateRow("Estimate") {
            HStack(spacing: 6) {
                TextField("—", text: $estimateMinutesDraft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                    .frame(width: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .focused($estimateFocused)
                    .onSubmit { commitEstimate() }
                    // Blur-commit: closing the inspector (X / Escape / selecting
                    // another row) or tabbing to another field drops focus while
                    // `task` is still the current one, so the typed value persists
                    // before any selection-swap resync can overwrite the draft.
                    .onChange(of: estimateFocused) { _, isFocused in
                        if !isFocused { commitEstimate() }
                    }
                    // Teardown backstop for the Mac modal, whose host removes the
                    // view rather than invoking `onClose`. `commitEstimate` re-derives
                    // the draft from the stored value, so double-firing is harmless.
                    .onDisappear { commitEstimate() }
                Text("min")
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
        }
    }

    /// Human-readable label for the scheduled block's span (`startAt`→`endAt`),
    /// distinct from the user estimate. nil when there is no valid timed block.
    var durationLabel: String? {
        guard let startAt = task.startAt, let endAt = task.endAt, endAt > startAt else {
            return nil
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: endAt.timeIntervalSince(startAt))
    }

    /// Renders a stored seconds estimate as a whole-minute string for the editor,
    /// or "" when there is no estimate. Inverse of the commit parse.
    static func minutesString(fromSeconds seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        return String(seconds / 60)
    }

    /// Parses the minutes draft and persists it to `estimatedDurationSeconds`
    /// (×60) with an `explicit` source, or clears both when empty/zero/invalid.
    /// Re-renders the draft from the stored value so an invalid entry snaps back.
    @MainActor
    func commitEstimate() {
        let trimmed = estimateMinutesDraft.trimmingCharacters(in: .whitespaces)
        if let minutes = Int(trimmed), minutes > 0 {
            task.estimatedDurationSeconds = minutes * 60
            task.durationSourceRaw = DurationSource.explicit.rawValue
        } else {
            task.estimatedDurationSeconds = nil
            task.durationSourceRaw = nil
        }
        save()
        estimateMinutesDraft = Self.minutesString(fromSeconds: task.estimatedDurationSeconds)
    }
}
