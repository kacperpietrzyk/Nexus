import NexusUI
import SwiftUI

/// Completion stats header for the cycle planner (Tranche 2 Plan C). Derived
/// display only — the numbers come from `CycleStatsModel.stats`, never stored.
struct CycleStatsHeader: View {
    let stats: CycleStatsModel.Stats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(stats.done) of \(stats.total) done")
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)

                Spacer(minLength: 8)

                if stats.addedAfterStart > 0 {
                    Text("+\(stats.addedAfterStart) added mid-cycle")
                        .nexusType(.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(NexusColor.Background.control)
                    Capsule()
                        .fill(NexusColor.Text.primary)
                        .frame(width: proxy.size.width * stats.completionFraction)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.done) of \(stats.total) tasks done")
    }
}
