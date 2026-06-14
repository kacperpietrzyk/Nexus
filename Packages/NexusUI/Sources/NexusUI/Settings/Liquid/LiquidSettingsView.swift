#if os(macOS)
import NexusCore
import SwiftUI

/// Two-pane macOS Settings view — left category rail + right detail pane.
///
/// Mounted as a direct `ContentView.destinationMain` destination (Task 9).
/// For now, build + lint only; not wired into the shell yet.
///
/// Theme preference and advanced-toggle are stored in `UserDefaults` via
/// `@AppStorage`, identical keys and defaults to `NexusSettingsView.macGeneralSection`
/// so behaviour is unchanged when this replaces the legacy Settings window.
public struct LiquidSettingsView: View {
    @Environment(\.macSettingsDependencies) private var deps
    @State private var selected: SettingsCategory = .general

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            SettingsCategoryRail(selected: $selected)

            Divider()
                .overlay(DS.ColorToken.strokeHairline)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail pane

    private var detailPane: some View {
        // Wrapped in a `NavigationStack` so embedded sub-views (ManageModels'
        // `NavigationLink("System prompt…")`) have a push ancestor. At the stack
        // root with nothing below it macOS shows no back button, so no extra
        // chrome leaks; a push (System prompt) gets a native back affordance.
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.l) {
                    detailHeader(for: selected)
                    detailContent(for: selected)
                }
                .padding(DS.Space.l)
                .frame(maxWidth: 720, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Header (serif, Stats-idiom)

    private func detailHeader(for category: SettingsCategory) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text("Settings")
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .textCase(.uppercase)
                .tracking(1.4)

            Text(category.title)
                .font(DS.FontToken.displayLarge)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Per-category content

    @ViewBuilder
    private func detailContent(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            GeneralPanel()
        case .sync:
            SyncPanel()
        case .tasks:
            TasksPanel()
        case .aiModels:
            AIModelsPanel()
        case .meetings:
            MeetingsPanel()
        case .advanced:
            AdvancedPanel()
        case .about:
            AboutPanel()
        }
    }
}

// MARK: - General panel

/// Theme picker + Advanced toggle panel.
///
/// Bindings mirror `NexusSettingsView.macGeneralSection` exactly:
/// `@AppStorage(NexusPreferences.Keys.theme)` → `String` raw-value,
/// `@AppStorage(NexusPreferences.Keys.advancedEnabled)` → `Bool`.
private struct GeneralPanel: View {
    @AppStorage(NexusPreferences.Keys.theme)
    private var theme: String = NexusTheme.amberDark.rawValue

    @AppStorage(NexusPreferences.Keys.advancedEnabled)
    private var advancedEnabled: Bool = false

    var body: some View {
        LiquidGlassCard("General") {
            VStack(spacing: 0) {
                // Theme row
                HStack {
                    Text("Theme")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Picker("Theme", selection: $theme) {
                        ForEach(NexusTheme.allCases, id: \.rawValue) { value in
                            Text(label(for: value)).tag(value.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text("Light mode arrives once the base tokens stabilize.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                // Advanced toggle row
                HStack {
                    Text("Show advanced features")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $advancedEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text("Reveals external access and advanced cloud-provider settings.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)
            }
        }
    }

    private func label(for theme: NexusTheme) -> String {
        switch theme {
        case .amberDark: return "Dark"
        }
    }
}

// MARK: - Sync panel

/// Read-only iCloud/CloudKit status panel.
///
/// Derives state from `deps.cloudKitEnabled` and `deps.cloudKitContainerIdentifier`,
/// mirroring the logic in `NexusSettingsView.macSyncSection`.
private struct SyncPanel: View {
    @Environment(\.macSettingsDependencies) private var deps

    var body: some View {
        LiquidGlassCard("iCloud Sync") {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    Image(systemName: deps.cloudKitEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(
                            deps.cloudKitEnabled
                                ? DS.ColorToken.textTertiary
                                : DS.ColorToken.textSecondary
                        )
                        .frame(width: 18, alignment: .center)

                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        HStack {
                            Text(deps.cloudKitEnabled ? "iCloud active" : "iCloud unavailable")
                                .font(DS.FontToken.body.weight(.semibold))
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Spacer()
                            if deps.cloudKitEnabled {
                                LiquidPill("Active", color: DS.ColorToken.accentGreen, filled: true)
                            } else {
                                LiquidPill("Unavailable", color: DS.ColorToken.statusNeutral)
                            }
                        }

                        if let container = deps.cloudKitContainerIdentifier {
                            Text(container)
                                .font(DS.FontToken.metadata)
                                .monospacedDigit()
                                .foregroundStyle(DS.ColorToken.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Text(
                            deps.cloudKitEnabled
                                ? "CloudKit private database is enabled."
                                : "Disabled in the local development environment."
                        )
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
            }
        }
    }
}

// MARK: - Tasks panel

/// Quiet hours + calendar-events toggle + Goals panel.
///
/// Quiet-hours `DatePicker`s bind to `deps.quietHoursStart` / `deps.quietHoursEnd`.
/// Calendar toggle uses `@AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled)`
/// (key `"nexus.calendar.eventsInTodayEnabled"`), mirroring `NexusSettingsView.macTasksSection`.
/// `GoalsSettingsState` is self-contained (`@Observable` + `UserDefaultsGoalsPreferencesStore`)
/// and is instantiated directly as `@State`, identical to the pattern in `NexusSettingsView`.
private struct TasksPanel: View {
    @Environment(\.macSettingsDependencies) private var deps

    @AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled)
    private var calendarEventsInTodayEnabled = false

    @State private var calendarPermission = CalendarPermissionState()
    @State private var goalsState = GoalsSettingsState()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            quietHoursCard
            goalsCard
        }
        .onAppear { calendarPermission.refresh() }
    }

    // MARK: Quiet hours card

    private var quietHoursCard: some View {
        LiquidGlassCard("Quiet hours") {
            VStack(spacing: 0) {
                if !deps.notificationsAuthorized {
                    notificationsDeniedBanner
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.m)

                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)
                }

                // Quiet hours from
                HStack {
                    Text("Quiet hours from")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    DatePicker("", selection: deps.quietHoursStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 102)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                // Quiet hours until
                HStack {
                    Text("Quiet hours until")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    DatePicker("", selection: deps.quietHoursEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(width: 102)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                // Calendar events toggle
                HStack {
                    Text("Show Calendar events in Today")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $calendarEventsInTodayEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: calendarEventsInTodayEnabled) { _, newValue in
                            handleCalendarToggleChange(newValue)
                        }
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                // Calendar permission status
                HStack {
                    Text("Calendar permissions")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    calendarPermissionStatusLabel
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text(
                    "Nexus reads events from the system Calendar in read-only mode."
                        + " It never creates or modifies anything."
                )
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.s)
            }
        }
    }

    // MARK: Goals card

    private var goalsCard: some View {
        @Bindable var goals = goalsState
        return LiquidGlassCard("Goals") {
            VStack(spacing: 0) {
                // Daily goal row
                HStack {
                    Text("Daily goal")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    goalStepper(value: $goals.dailyTarget)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                // Weekly goal row
                HStack {
                    Text("Weekly goal")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    goalStepper(value: $goals.weeklyTarget)
                }
                .frame(minHeight: 44)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text(
                    "Daily and weekly completion targets drive the Goals card on the productivity dashboard."
                        + " Set a target to 0 to hide it."
                )
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, DS.Space.s)
            }
        }
    }

    // MARK: Helpers

    private func goalStepper(value: Binding<Int>) -> some View {
        HStack(spacing: DS.Space.m) {
            Text(goalLabel(for: value.wrappedValue))
                .font(DS.FontToken.body.weight(.medium))
                .foregroundStyle(DS.ColorToken.textSecondary)
                .monospacedDigit()
            Stepper("", value: value, in: 0...99)
                .labelsHidden()
        }
    }

    private func goalLabel(for target: Int) -> String {
        switch target {
        case 0: return "Off"
        case 1: return "1 task"
        default: return "\(target) tasks"
        }
    }

    private func handleCalendarToggleChange(_ newValue: Bool) {
        guard newValue else { return }
        switch calendarPermission.status {
        case .notDetermined:
            Task { await calendarPermission.requestAccess() }
        case .denied, .restricted:
            calendarEventsInTodayEnabled = false
        case .fullAccess, .writeOnly:
            break
        }
    }

    @ViewBuilder
    private var calendarPermissionStatusLabel: some View {
        switch calendarPermission.status {
        case .notDetermined:
            Text("Not requested")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textMuted)
        case .denied:
            Text("Denied")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
        case .restricted:
            Text("Restricted")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
        case .fullAccess:
            Text("Granted")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
        case .writeOnly:
            Text("Write only")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textMuted)
        }
    }

    @ViewBuilder
    private var notificationsDeniedBanner: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label("Notifications disabled", systemImage: "bell.slash.fill")
                .foregroundStyle(DS.ColorToken.textPrimary)
                .font(DS.FontToken.body.weight(.bold))
            Button("Open System Settings") {
                openSystemSettings()
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, DS.Space.s)
    }

    private func openSystemSettings() {
        #if os(macOS)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
        #endif
    }
}

// MARK: - Meetings panel

/// Renders the composed `meetingsSettingsContent` thunk from deps chromeless.
private struct MeetingsPanel: View {
    @Environment(\.macSettingsDependencies) private var deps

    var body: some View {
        deps.meetingsSettingsContent()
            .environment(\.settingsDetailEmbedded, true)
    }
}

// MARK: - Advanced panel

/// External access (MCP) sub-view + data export row.
private struct AdvancedPanel: View {
    @Environment(\.macSettingsDependencies) private var deps

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            deps.externalAccessContent()
                .environment(\.settingsDetailEmbedded, true)

            LiquidGlassCard("Export") {
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text("Export to Folder…")
                                .font(DS.FontToken.body)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Text("Export all tasks and notes as Markdown files.")
                                .font(DS.FontToken.caption)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                        }
                        Spacer()
                        NexusButton(
                            variant: .default,
                            size: .sm,
                            action: { deps.onExportRequested() },
                            label: { Text("Export to Folder…") }
                        )
                    }
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

// MARK: - About panel

/// Version + build + core read-only rows.
private struct AboutPanel: View {

    private var bundleShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }

    var body: some View {
        LiquidGlassCard("About") {
            VStack(spacing: 0) {
                readOnlyRow("Nexus", value: bundleShortVersion)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                readOnlyRow("Build", value: bundleVersion)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                readOnlyRow("Core", value: NexusCore.version)
            }
        }
    }

    private func readOnlyRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer()
            Text(value)
                .font(DS.FontToken.metadata)
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Preview

#Preview("LiquidSettingsView") {
    LiquidSettingsView()
        .environment(\.macSettingsDependencies, .empty)
        .frame(width: 860, height: 600)
        .background(DS.ColorToken.backgroundApp)
}
#endif
