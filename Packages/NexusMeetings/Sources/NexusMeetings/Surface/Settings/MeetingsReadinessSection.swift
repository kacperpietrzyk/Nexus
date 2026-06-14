#if os(macOS) && canImport(ServiceManagement)
import Combine
import NexusUI
import SwiftUI

/// Settings section showing the readiness status of the Meetings system.
///
/// Renders each `ReadinessSection` from `MeetingsReadinessViewModel` as a
/// `LiquidGlassCard` block with one Liquid row per `ReadinessRow`.
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
            LiquidGlassCard(section.title) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider()
                                .overlay(DS.ColorToken.strokeHairline)
                        }
                        rowView(row)
                    }
                }
            }
        }
        .onAppear {
            viewModel.requestHelperRefresh()
            viewModel.refresh()
        }
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
        HStack {
            Text(row.title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer()
            HStack(spacing: DS.Space.m) {
                if let detail = row.detail {
                    Text(detail)
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textMuted)
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
        .frame(minHeight: 44)
    }

    @ViewBuilder
    private func statusIcon(_ state: ReadinessRowState) -> some View {
        switch state {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(DS.ColorToken.statusSuccess)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.ColorToken.textMuted)
        case .error:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(DS.ColorToken.statusDanger)
        case .info:
            Image(systemName: "info.circle")
                .foregroundStyle(DS.ColorToken.textMuted)
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .tint(DS.ColorToken.textSecondary)
        }
    }

    private func actionLabel(_ action: ReadinessRowAction) -> String? {
        switch action {
        case .requestMicrophone: "Request"
        case .openAccessibilitySettings: "Open Settings"
        case .downloadModel: "Download"
        case .downloadAllModels: "Download All"
        case .startHelper: nil
        case .enableAutoRecord: nil
        case .info: nil
        }
    }
}
#endif
