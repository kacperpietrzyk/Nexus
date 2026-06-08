import NexusUI
import SwiftUI

// MARK: - Route placeholder

// The eyebrow + display-title + body "unavailable" card used by `routeSwitch`
// when a host shell did not supply a destination's content (e.g. Meetings).
// Lifted out of `TodayDashboard.swift` purely for file-length headroom —
// the same mechanical-move idiom as the `+DigestData` / `+Standalone` splits.
// `internal` (was `private`) so the in-file call site still resolves it.

extension TodayDashboard {
    func placeholderScroll(eyebrow: String, title: String, body: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(eyebrow.uppercased())
                        .nexusType(.eyebrow)
                        .foregroundStyle(NexusColor.Text.muted)

                    Text(title)
                        .font(NexusType.display)
                        .foregroundStyle(NexusColor.Text.primary)

                    Text(body)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(NexusColor.Line.regular, lineWidth: 1))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }
}
