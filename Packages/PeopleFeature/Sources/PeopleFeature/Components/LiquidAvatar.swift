import NexusUI
import SwiftUI

/// Achromatic glass avatar pill (Liquid language): initials on a selected-glass
/// fill with a default-stroke rim. Decorative — the adjacent text carries the
/// name for accessibility. Internal to PeopleFeature; sized by the call site.
struct LiquidAvatar: View {
    let name: String
    var size: CGFloat = 30

    var body: some View {
        Text(PersonInitials.initials(from: name))
            // Scales with the pill; 0.38 keeps two letters inside the circle
            // at both row (30 pt) and profile-header (48 pt) sizes — visual
            // calibration, no DS token at this scale.
            .font(.system(size: max(9, size * 0.38), weight: .semibold))
            .foregroundStyle(DS.ColorToken.textSecondary)
            .frame(width: size, height: size)
            .background(DS.ColorToken.glassSelected, in: Circle())
            .overlay(Circle().strokeBorder(DS.ColorToken.strokeDefault, lineWidth: 1))
            .accessibilityHidden(true)
    }
}
