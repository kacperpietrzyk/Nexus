import SwiftUI

#if !os(watchOS)

import NexusAgentTools

public struct AgentActivityLogView: View {
    public let log: AgentActivityLog

    public init(log: AgentActivityLog) {
        self.log = log
    }

    public var body: some View {
        if log.entries.isEmpty {
            NexusEmptyState(
                systemImage: "wrench.and.screwdriver",
                title: "No activity yet",
                message: "Tools will appear here when an MCP client uses Nexus."
            )
        } else {
            ForEach(log.entries.reversed()) { entry in
                row(entry)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: AgentActivityEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.timestamp, style: .time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            Text(entry.toolName)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)

            statusIcon(for: entry.resultStatus)

            Text("\(entry.durationMs)ms")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statusIcon(for status: ResultStatus) -> some View {
        switch status {
        case .ok:
            // §3 categorical: Semantic.positive → Text.secondary; the
            // `checkmark.circle.fill` glyph shape carries the ok semantic
            // (oracle has no hue, §2 LabPalette.read).
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(NexusColor.Text.secondary)
                .font(.caption)
        case .errorCode(let code):
            HStack(spacing: 4) {
                // §3 categorical: Semantic.negative → Text.primary; the
                // `xmark.circle.fill` glyph shape carries the error
                // semantic, ink steps to the most-salient (§2
                // LabPalette.ink); the code text follows the same step.
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(NexusColor.Text.primary)
                Text("\(code)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }
}

#endif
