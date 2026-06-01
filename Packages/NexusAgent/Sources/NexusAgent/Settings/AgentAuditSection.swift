import NexusUI
import SwiftUI

public struct AgentAuditSection: View {
    public let context: AgentSettingsContext
    @StateObject private var viewModel: AgentAuditViewModel

    public init(context: AgentSettingsContext) {
        self.context = context
        _viewModel = StateObject(
            wrappedValue: AgentAuditViewModel(
                context: context.auditContext,
                undoCoordinator: context.undoCoordinator
            )
        )
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Recent autonomous mutations")
            NexusSettingsCard {
                if viewModel.entries.isEmpty {
                    NexusEmptyState(
                        systemImage: "clock.arrow.circlepath",
                        title: "No autonomous mutations yet."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                NexusSettingsDivider()
                            }
                            auditRow(entry)
                                .padding(.horizontal, NexusSpacing.s4)
                                .padding(.vertical, NexusSpacing.s3)
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.reload()
        }
    }

    private func auditRow(_ entry: AgentAuditLog) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.toolName)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)

                Text(entry.timestamp, style: .relative)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }

            Spacer(minLength: 12)

            trailingControl(for: entry)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func trailingControl(for entry: AgentAuditLog) -> some View {
        if entry.undoneAt != nil {
            // §3 categorical: Semantic.positive → Text.secondary. "Undone"
            // is a settled-good state label (oracle has no hue),
            // structurally parallel to slice-1 `Text("Granted")` → §2
            // LabPalette.read.
            Text("Undone")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.secondary)
        } else if entry.inverseAction != nil {
            Button("Undo") {
                Task {
                    await viewModel.undo(id: entry.id)
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isUndoing)
        } else {
            Text("Read-only")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
        }
    }
}
