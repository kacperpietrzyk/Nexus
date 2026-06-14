import SwiftUI

#if !os(watchOS)

// swiftlint:disable file_length

import NexusAI
import NexusCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// swiftlint:disable type_body_length
/// iOS Settings root (mounted by `NexusiOSApp` → `SettingsTab`). On macOS,
/// Settings now lives in-shell as `LiquidSettingsView`; this view's former
/// macOS branch was retired, so the body is the iOS scrollable form.
public struct NexusSettingsView: View {
    public let cloudKitEnabled: Bool
    public let containerIdentifier: String
    public let onExportRequested: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveData: AISettingsLiveData?
    @State private var calendarPermission = CalendarPermissionState()
    @State private var goalsState = GoalsSettingsState()
    @AppStorage(NexusPreferences.Keys.theme) private var theme: String = NexusTheme.amberDark.rawValue
    @AppStorage(NexusPreferences.Keys.advancedEnabled) private var advancedEnabled: Bool = false
    @AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled) private var calendarEventsInTodayEnabled = false

    /// Optional Tasks-section wiring. When `notificationsAuthorized` is non-nil
    /// the Tasks section renders — apps inject this from a
    /// `NotificationPermissionState` (TasksFeature) at the composition root.
    /// `false` triggers the "Notifications disabled" banner.
    private let notificationsAuthorized: Bool?
    private let quietHoursStartTime: Binding<Date>?
    private let quietHoursEndTime: Binding<Date>?
    private let agentSettingsContent: AnyView?
    private let meetingsSettingsContent: AnyView?
    private let manageModelsContent: AnyView?

    public init(
        cloudKitEnabled: Bool,
        containerIdentifier: String,
        aiRouter: AIRouter? = nil,
        notificationsAuthorized: Bool? = nil,
        quietHoursStartTime: Binding<Date>? = nil,
        quietHoursEndTime: Binding<Date>? = nil,
        agentSettingsContent: AnyView? = nil,
        meetingsSettingsContent: AnyView? = nil,
        manageModelsContent: AnyView? = nil,
        onExportRequested: @escaping () -> Void
    ) {
        self.cloudKitEnabled = cloudKitEnabled
        self.containerIdentifier = containerIdentifier
        self.notificationsAuthorized = notificationsAuthorized
        self.quietHoursStartTime = quietHoursStartTime
        self.quietHoursEndTime = quietHoursEndTime
        self.agentSettingsContent = agentSettingsContent
        self.meetingsSettingsContent = meetingsSettingsContent
        self.manageModelsContent = manageModelsContent
        self.onExportRequested = onExportRequested
        _liveData = State(initialValue: aiRouter.map(AISettingsLiveData.init(router:)))
    }

    public var body: some View {
        // macOS now renders Settings via the in-shell `LiquidSettingsView`
        // (NexusUI/Settings/Liquid). This view is mounted only on iOS
        // (`NexusiOSApp` → `SettingsTab`), so the body is the iOS form.
        settingsForm
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

    private func label(for theme: NexusTheme) -> String {
        switch theme {
        case .amberDark: return "Dark"
        }
    }

    private var bundleShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }

    /// iOS Settings root. Mirrors the macOS card idiom (`nexusSettingsCardSectionHeader`
    /// + `NexusSettingsCard`) inside a `ScrollView` rather than a grouped `Form`, so the
    /// flat-tier / contained-shadow Linear surface is identical across platforms. The
    /// section-`Section{}` structs (General/Sync/Advanced/About/AppleWatch/ExternalAccessInfo)
    /// are intentionally NOT used on this path — they remain for their tests — and the
    /// content is composed inline as `iosXxxSection` builders below.
    private var settingsForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NexusSpacing.s7) {
                iosGeneralSection
                iosSyncSection
                iosTasksSection
                iosGoalsSection
                #if os(iOS)
                iosAppleWatchSection
                #endif
                AISettingsSection(liveData: liveData)
                iosNavigationSection(
                    title: "Models",
                    label: "Manage Models",
                    systemImage: "cpu",
                    destination: manageModelsContent,
                    footer: "Downloaded local models, chat/embedder assignment, memory, and resource release."
                )
                iosNavigationSection(
                    title: "Agent",
                    label: "Agent",
                    systemImage: "sparkles",
                    destination: agentSettingsContent,
                    footer: "Agent memory, indexing, schedules, audit, and provider routing."
                )
                iosNavigationSection(
                    title: "Meetings",
                    label: "Meetings",
                    systemImage: "person.wave.2",
                    destination: meetingsSettingsContent,
                    footer: "Recording, transcription, summary prompts, retention, and imports."
                )
                iosExternalAccessSection
                iosAdvancedSection
                iosAboutSection
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, NexusSpacing.s5)
            .padding(.top, NexusSpacing.s5)
            .padding(.bottom, NexusSpacing.s8)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            calendarPermission.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                calendarPermission.refresh()
            }
        }
        .task { await liveData?.refresh() }
    }

    private func iosSettingsSection<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader(title)
            NexusSettingsCard {
                content()
            }
            if let footer {
                Text(footer)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                    .padding(.horizontal, NexusSpacing.s4)
            }
        }
    }

    private func iosHelperText(_ text: String) -> some View {
        Text(text)
            .font(NexusType.caption)
            .foregroundStyle(NexusColor.Text.muted)
            .padding(.horizontal, NexusSpacing.s4)
            .padding(.vertical, NexusSpacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iosGeneralSection: some View {
        iosSettingsSection("General") {
            VStack(spacing: 0) {
                NexusSettingsRow("Theme") {
                    Picker("Theme", selection: $theme) {
                        ForEach(NexusTheme.allCases, id: \.rawValue) { value in
                            Text(label(for: value)).tag(value.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(NexusColor.Text.primary)
                }
                NexusSettingsDivider()
                iosHelperText("Light mode arrives once the base tokens stabilize.")
                NexusSettingsDivider()
                NexusSettingsRow("Show advanced features") {
                    Toggle("", isOn: $advancedEnabled)
                        .labelsHidden()
                }
                NexusSettingsDivider()
                iosHelperText("Reveals external access and advanced cloud-provider settings.")
            }
        }
    }

    private var iosSyncSection: some View {
        iosSettingsSection("Sync") {
            HStack(alignment: .top, spacing: NexusSpacing.s3) {
                Image(systemName: cloudKitEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(cloudKitEnabled ? NexusColor.Text.tertiary : NexusColor.Text.secondary)
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: NexusSpacing.s2) {
                    Text(cloudKitEnabled ? "iCloud active" : "iCloud unavailable")
                        .font(NexusType.bodySmall.weight(.semibold))
                        .foregroundStyle(NexusColor.Text.primary)
                    Text(containerIdentifier)
                        .font(NexusType.mono)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(cloudKitEnabled ? "CloudKit private database is enabled." : "Disabled in the local development environment.")
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NexusSpacing.s4)
        }
    }

    @ViewBuilder
    private var iosTasksSection: some View {
        if let config = tasksConfig {
            iosSettingsSection(
                "Tasks",
                footer: "Nexus reads events from the system Calendar in read-only mode. It never creates or modifies anything."
            ) {
                VStack(spacing: 0) {
                    if !config.authorized {
                        deniedBanner
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, NexusSpacing.s4)
                            .padding(.vertical, NexusSpacing.s3)
                        NexusSettingsDivider()
                    }
                    NexusSettingsRow("Quiet hours from") {
                        DatePicker("", selection: config.start, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    NexusSettingsDivider()
                    NexusSettingsRow("Quiet hours until") {
                        DatePicker("", selection: config.end, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    NexusSettingsDivider()
                    NexusSettingsRow("Show Calendar events in Today") {
                        Toggle("", isOn: $calendarEventsInTodayEnabled)
                            .labelsHidden()
                            .onChange(of: calendarEventsInTodayEnabled) { _, newValue in
                                handleCalendarToggleChange(newValue)
                            }
                    }
                    if calendarPermission.status == .denied || calendarPermission.status == .restricted {
                        NexusSettingsDivider()
                        iosCalendarDeniedRow
                    }
                    NexusSettingsDivider()
                    NexusSettingsRow("Calendar permissions") {
                        HStack(spacing: NexusSpacing.s3) {
                            calendarPermissionStatusLabel
                                .font(NexusType.bodySmall.weight(.medium))
                            if calendarPermission.status == .denied || calendarPermission.status == .restricted {
                                openCalendarSettingsButton
                            }
                        }
                    }
                }
            }
        }
    }

    private var iosGoalsSection: some View {
        iosSettingsSection(
            "Goals",
            footer: "Daily and weekly completion targets drive the Goals card on the productivity dashboard. "
                + "Set a target to 0 to hide it."
        ) {
            goalsRows
        }
    }

    private var goalsRows: some View {
        @Bindable var goals = goalsState
        return VStack(spacing: 0) {
            NexusSettingsRow("Daily goal") {
                goalStepper(value: $goals.dailyTarget)
            }
            NexusSettingsDivider()
            NexusSettingsRow("Weekly goal") {
                goalStepper(value: $goals.weeklyTarget)
            }
        }
    }

    private func goalStepper(value: Binding<Int>) -> some View {
        HStack(spacing: NexusSpacing.s3) {
            Text(goalLabel(for: value.wrappedValue))
                .font(NexusType.bodySmall.weight(.medium))
                .foregroundStyle(NexusColor.Text.secondary)
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

    private var iosCalendarDeniedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: NexusSpacing.s3) {
            // §3: the warning glyph shape carries the semantic; hue dropped to
            // the achromatic ink ladder.
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NexusColor.Text.secondary)
            VStack(alignment: .leading, spacing: NexusSpacing.s1) {
                Text("Calendar access disabled")
                    .font(NexusType.bodySmall.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                Text("Enable permission in System Settings to see events in Today.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
            Spacer(minLength: NexusSpacing.s2)
            openCalendarSettingsButton
        }
        .padding(.horizontal, NexusSpacing.s4)
        .padding(.vertical, NexusSpacing.s3)
    }

    #if os(iOS)
    private var iosAppleWatchSection: some View {
        iosSettingsSection("Apple Watch") {
            VStack(alignment: .leading, spacing: NexusSpacing.s1) {
                Text("Powiadomienia o zadaniach")
                    .font(NexusType.bodySmall.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                Text(
                    "Uprawnienia konfigurujesz w aplikacji Watch na iPhone — "
                        + "Powiadomienia → Nexus."
                )
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(NexusSpacing.s4)
        }
    }
    #endif

    @ViewBuilder
    private func iosNavigationSection(
        title: String,
        label: String,
        systemImage: String,
        destination: AnyView?,
        footer: String
    ) -> some View {
        if let destination {
            iosSettingsSection(title, footer: footer) {
                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: NexusSpacing.s3) {
                        Image(systemName: systemImage)
                            .frame(width: 18)
                        Text(label)
                            .font(NexusType.bodySmall.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NexusColor.Text.muted)
                    }
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, NexusSpacing.s4)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var iosExternalAccessSection: some View {
        if advancedEnabled {
            iosSettingsSection("External Access") {
                Text("MCP server is available on macOS only. To enable external agent access, open Nexus on your Mac.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(NexusSpacing.s4)
            }
        }
    }

    private var iosAdvancedSection: some View {
        iosSettingsSection("Advanced") {
            Button(action: onExportRequested) {
                HStack(spacing: NexusSpacing.s3) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 18)
                    Text("Export to Folder…")
                        .font(NexusType.bodySmall.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(NexusColor.Text.primary)
                .padding(.horizontal, NexusSpacing.s4)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }

    private var iosAboutSection: some View {
        iosSettingsSection("About") {
            VStack(spacing: 0) {
                iosReadOnlyRow("Nexus", value: bundleShortVersion)
                NexusSettingsDivider()
                iosReadOnlyRow("Build", value: bundleVersion)
                NexusSettingsDivider()
                iosReadOnlyRow("Core", value: NexusCore.version)
            }
        }
    }

    private func iosReadOnlyRow(_ title: String, value: String) -> some View {
        NexusSettingsRow(title) {
            Text(value)
                .font(NexusType.bodySmall.weight(.medium))
                .foregroundStyle(NexusColor.Text.secondary)
        }
    }

    /// Bundles the three Tasks-section params so the section can be gated
    /// with a single `if let`. Section is suppressed entirely when any of
    /// the three is nil — apps that have not yet wired quiet-hours
    /// bindings simply pass nil and the section disappears.
    private struct TasksConfig {
        let authorized: Bool
        let start: Binding<Date>
        let end: Binding<Date>
    }

    private var tasksConfig: TasksConfig? {
        guard let authorized = notificationsAuthorized,
            let start = quietHoursStartTime,
            let end = quietHoursEndTime
        else {
            return nil
        }
        return TasksConfig(authorized: authorized, start: start, end: end)
    }

    @ViewBuilder
    private var openCalendarSettingsButton: some View {
        #if os(macOS)
        Button("Open Settings", action: openCalendarSettings)
            .buttonStyle(.link)
        #else
        Button("Open Settings", action: openCalendarSettings)
        #endif
    }

    @ViewBuilder
    private var calendarPermissionStatusLabel: some View {
        // §3 categorical-signal row: permission state has no oracle glyph
        // equivalent here, so it resolves to the achromatic ink ladder
        // stepped by importance (NOT hue). Denied/Restricted carry the
        // most weight (action needed) → `Text.primary`; Granted is the
        // settled-good state → `Text.secondary`; Not-requested/Write-only
        // are low-salience → `Text.muted`.
        switch calendarPermission.status {
        case .notDetermined:
            Text("Not requested")
                .foregroundStyle(NexusColor.Text.muted)
        case .denied:
            Text("Denied")
                .foregroundStyle(NexusColor.Text.primary)
        case .restricted:
            Text("Restricted")
                .foregroundStyle(NexusColor.Text.primary)
        case .fullAccess:
            Text("Granted")
                .foregroundStyle(NexusColor.Text.secondary)
        case .writeOnly:
            Text("Write only")
                .foregroundStyle(NexusColor.Text.muted)
        }
    }

    @ViewBuilder
    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            // §3 emphasis row: hue removed; the `bell.slash.fill` glyph
            // shape already carries the negative semantic, and the
            // heavier font weight + `Text.primary` ink step restore the
            // lost salience without color.
            Label("Notifications disabled", systemImage: "bell.slash.fill")
                .foregroundStyle(NexusColor.Text.primary)
                .font(.subheadline.weight(.bold))
            Button("Open System Settings", action: openSystemSettings)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        let candidates: [String] = [
            // Modern (System Settings.app, Ventura+):
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            // Legacy (System Preferences.app, Monterey and earlier):
            "x-apple.systempreferences:com.apple.preference.notifications",
            // Last resort: open System Settings root
            "x-apple.systempreferences:",
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        // All candidates failed — silently no-op. The "Open Settings" button
        // is a convenience; user can navigate manually.
        #endif
    }

    private func openCalendarSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        let candidates: [String] = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.preference.security",
            "x-apple.systempreferences:",
        ]
        for raw in candidates {
            guard let url = URL(string: raw) else { continue }
            if NSWorkspace.shared.open(url) { return }
        }
        #endif
    }
}
// swiftlint:enable type_body_length

@MainActor
@ViewBuilder
func nexusSettingsSectionHeader(_ title: String) -> some View {
    // Eyebrow token: Inter-SemiBold 10 / tracking 1.8 / uppercase / Text.muted.
    Text(title)
        .nexusType(NexusType.Metrics.eyebrow)
        .foregroundStyle(NexusColor.Text.muted)
}

#Preview("Settings") {
    NexusSettingsView(
        cloudKitEnabled: false,
        containerIdentifier: "iCloud.com.kacperpietrzyk.Nexus",
        onExportRequested: {}
    )
}

#Preview("Settings — denied notifications") {
    @Previewable @State var start =
        Calendar.current.date(
            bySettingHour: 22, minute: 0, second: 0, of: .now
        ) ?? .now
    @Previewable @State var end =
        Calendar.current.date(
            bySettingHour: 7, minute: 0, second: 0, of: .now
        ) ?? .now
    NexusSettingsView(
        cloudKitEnabled: false,
        containerIdentifier: "iCloud.com.kacperpietrzyk.Nexus",
        notificationsAuthorized: false,
        quietHoursStartTime: $start,
        quietHoursEndTime: $end,
        onExportRequested: {}
    )
}

#endif
