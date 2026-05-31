import NexusAI
import NexusAgent
import NexusMeetings
import NexusUI
import SwiftUI
import TasksFeature

struct SettingsTab: View {
    let cloudKitEnabled: Bool
    let containerIdentifier: String
    let aiRouter: AIRouter?
    let permissionState: NotificationPermissionState
    let agentSettingsContext: AgentSettingsContext?
    let meetingsComposition: MeetingsComposition?
    let manageModelsContent: AnyView?
    @Binding var quietHoursStartTime: Date
    @Binding var quietHoursEndTime: Date
    let onExportRequested: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            if let aiRouter {
                NexusSettingsView(
                    cloudKitEnabled: cloudKitEnabled,
                    containerIdentifier: containerIdentifier,
                    aiRouter: aiRouter,
                    notificationsAuthorized: permissionState.status != .denied,
                    quietHoursStartTime: $quietHoursStartTime,
                    quietHoursEndTime: $quietHoursEndTime,
                    agentSettingsContent: agentSettingsContext.map {
                        AnyView(AgentSettingsView(context: $0))
                    },
                    meetingsSettingsContent: meetingsComposition.map {
                        AnyView(
                            MeetingsSettingsSection(
                                composition: $0,
                                helperViewModel: nil
                            )
                        )
                    },
                    manageModelsContent: manageModelsContent,
                    onExportRequested: onExportRequested
                )
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top) {
                    settingsHeader
                }
                .toolbarBackground(NexusColor.Background.base, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .task { await permissionState.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        _Concurrency.Task { await permissionState.refresh() }
                    }
                }
            } else {
                ContentUnavailableView("Settings unavailable", systemImage: "gearshape")
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ProductivityDashboardView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NexusColor.Text.secondary)
                        .frame(width: 30, height: 30)
                        .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: NexusRadius.r1))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Productivity Stats")
                            .nexusType(.bodySmall)
                            .foregroundStyle(NexusColor.Text.primary)
                        Text("Streaks, completions, projects")
                            .nexusType(.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NexusColor.Text.muted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: NexusRadius.r3))
                .overlay {
                    RoundedRectangle(cornerRadius: NexusRadius.r3)
                        .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(NexusColor.Background.panel)
    }
}
