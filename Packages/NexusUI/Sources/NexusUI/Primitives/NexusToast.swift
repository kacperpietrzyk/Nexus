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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(NexusColor.Text.tertiary)
            Text(message)
                .font(NexusType.meta)
                .foregroundStyle(NexusColor.Text.secondary)
            if undo {
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1, height: 12)
                Text("Cofnij")
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .nexusGlass(.elevated, in: Capsule())
    }
}

#Preview {
    VStack(spacing: 12) {
        NexusToast(icon: "checkmark.circle", message: "Zadanie zapisane")
        NexusToast(icon: "arrow.uturn.backward", message: "Cofnięto", undo: true)
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
