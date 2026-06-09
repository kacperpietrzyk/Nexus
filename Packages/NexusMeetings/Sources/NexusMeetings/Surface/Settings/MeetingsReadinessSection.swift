#if os(macOS) && canImport(ServiceManagement)
import Combine
import NexusUI
import SwiftUI

/// Settings section showing the readiness status of the Meetings system.
///
/// Renders each `ReadinessSection` from `MeetingsReadinessViewModel` as a
/// `NexusSettingsCard` block with one `NexusSettingsRow` per `ReadinessRow`.
/// Each row shows a status icon on the left and an optional action button
/// (`NexusButton(.outline, .sm)`) on the right. Refresh is triggered on
/// `.onAppear`.
public struct MeetingsReadinessSection: View {
    @State private var viewModel: MeetingsReadinessViewModel

    public init(viewModel: MeetingsReadinessViewModel = MeetingsReadinessViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ForEach(viewModel.sections) { section in
            VStack(alignment: .leading, spacing: NexusSpacing.s3) {
                nexusSettingsCardSectionHeader(section.title)
                NexusSettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                NexusSettingsDivider()
                            }
                            rowView(row)
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.refresh() }
        // Refresh whenever the helper posts a fresh snapshot so the panel
        // updates live without requiring the user to re-open Settings.
        .onReceive(
            DistributedNotificationCenter.default()
                .publisher(for: MeetingsReadinessNotification.readinessDidChange)
        ) { _ in
            viewModel.refresh()
        }
    }

    @ViewBuilder
    private func rowView(_ row: ReadinessRow) -> some View {
        NexusSettingsRow(row.title) {
            HStack(spacing: NexusSpacing.s3) {
                if let detail = row.detail {
                    Text(detail)
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.muted)
                }
                if let action = row.action, let label = actionLabel(action) {
                    NexusButton(variant: .outline, size: .sm) {
                        viewModel.perform(action)
                    } label: {
                        Text(label)
                    }
                }
                statusIcon(row.state)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ state: ReadinessRowState) -> some View {
        switch state {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(NexusColor.Status.success)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NexusColor.Text.muted)
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(NexusColor.Status.danger)
        case .info:
            Image(systemName: "info.circle")
                .foregroundStyle(NexusColor.Text.muted)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .tint(NexusColor.Text.secondary)
        }
    }

    private func actionLabel(_ action: ReadinessRowAction) -> String? {
        switch action {
        case .requestMicrophone: "Request"
        case .openAccessibilitySettings: "Open Settings"
        case .downloadModel: "Download"
        case .downloadAllModels: "Download All"
        case .startHelper: "Start"
        case .enableAutoRecord: "Enable"
        case .info: nil
        }
    }
}
#endif
