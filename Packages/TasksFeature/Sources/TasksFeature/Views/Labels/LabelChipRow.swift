import NexusCore
import NexusUI
import SwiftUI

/// Renders a `Label` as an achromatic chip (LabKit — glyph, not color, per spec
/// §4.4). The remove affordance is shown only when `onRemove` is supplied AND the
/// label is user-created: system labels are non-deletable from the UI (spec §7),
/// and in "add" pickers the chip is decorative (the row's outer button handles
/// the tap), so no nested remove button is rendered.
struct LabelChipRow: View {
    let label: TaskLabel
    var onRemove: (() -> Void)?

    init(label: TaskLabel, onRemove: (() -> Void)? = nil) {
        self.label = label
        self.onRemove = onRemove
    }

    var body: some View {
        if let onRemove, !label.isSystem {
            NexusChip(label.name, systemImage: glyph, tone: tone, onRemove: onRemove)
        } else {
            NexusChip(label.name, systemImage: glyph, tone: tone)
        }
    }

    /// Falls back to a neutral tag glyph when a label carries no `glyphKey`.
    private var glyph: String {
        label.glyphKey.isEmpty ? "tag" : label.glyphKey
    }

    /// `gate` labels read as the single active marker (lime rim); domain/free
    /// stay neutral chrome so lime economy holds (one accent per surface).
    private var tone: NexusChipTone {
        label.group == .gate ? .accent : .neutral
    }
}
