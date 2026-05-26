import SwiftUI

#if !os(watchOS)

public struct StorageUsageBar: View {
    let usedGB: Double
    let totalGB: Double

    public init(usedGB: Double, totalGB: Double) {
        self.usedGB = usedGB
        self.totalGB = totalGB
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "%.1f GB", usedGB))
                    .bold()
                ProgressView(value: usedGB, total: max(totalGB, 1))
                Text(String(format: "of %.0f GB", totalGB))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("AI models on disk")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#endif
