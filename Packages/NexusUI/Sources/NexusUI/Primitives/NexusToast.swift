import SwiftUI

/// Ephemeral confirmation pill (LabKit `LabToast`).
///
/// Pair with `.transition(.nexusToast)` at the call site and fire / clear it
/// inside `withAnimation(NexusMotion.standard)` (in) and
/// `withAnimation(NexusMotion.exit)` (out) so the slide+fade matches the
/// LabKit motion vocabulary.
public struct NexusToast: View {
    public let icon: String
    public let message: String
    public var undo: Bool = false

    public init(icon: String, message: String, undo: Bool = false) {
        self.icon = icon
        self.message = message
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Leading status stripe: lime for a primary confirmation, info for an
            // undoable action. The stripe is the only colored accent on the toast.
            Rectangle()
                .fill(stripeColor)
                .frame(width: 3)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(NexusColor.Text.tertiary)
                Text(message)
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Text.primary)
                if undo {
                    Rectangle()
                        .fill(NexusColor.Line.regular)
                        .frame(width: 1, height: 12)
                    Text("Undo")
                        .font(NexusType.meta)
                        .foregroundStyle(NexusColor.Text.primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
        }
        .background(NexusColor.Background.raised)
        .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r1, style: .continuous)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        )
        .nexusShadow(NexusShadow.pop)
    }

    /// The leading stripe color. A confirmation toast is the surface's single
    /// primary action, so it earns the lime accent; an undoable action is
    /// informational and uses the neutral `Status.info` cyan instead.
    private var stripeColor: Color {
        undo ? NexusColor.Status.info : NexusColor.Accent.lime
    }
}

#Preview {
    VStack(spacing: 12) {
        NexusToast(icon: "checkmark.circle", message: "Task saved")
        NexusToast(icon: "arrow.uturn.backward", message: "Undone", undo: true)
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
