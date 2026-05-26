import SwiftUI

#if !os(watchOS)

// swiftlint:disable file_length

import NexusAI
import NexusAgentTools
import NexusCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// swiftlint:disable type_body_length
/// Single SwiftUI scene shared by Mac (`Settings { }`) and iOS (`.sheet { }`). Sections are
/// stacked vertically inside a `Form` — SwiftUI renders this as a side-by-side panel on Mac and a
/// grouped form on iOS without further conditionals.
public struct NexusSettingsView: View {
    public let cloudKitEnabled: Bool
    public let containerIdentifier: String
    public let onExportRequested: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveData: AISettingsLiveData?
    @State private var calendarPermission = CalendarPermissionState()
    @AppStorage(NexusPreferences.Keys.theme) private var theme: String = NexusTheme.amberDark.rawValue
    @AppStorage(NexusPreferences.Keys.advancedEnabled) private var advancedEnabled: Bool = false
    @AppStorage(NexusPreferences.Keys.calendarEventsInTodayEnabled) private var calendarEventsInTodayEnabled = false

    /// Optional Tasks-section wiring. When `notificationsAuthorized` is non-nil
    /// the Tasks section renders — apps inject this from a
    /// `NotificationPermissionState` (TasksFeature) at the composition root.
    /// `false` triggers the "Notyfikacje wyłączone" banner.
    private let notificationsAuthorized: Bool?
    private let quietHoursStartTime: Binding<Date>?
    private let quietHoursEndTime: Binding<Date>?
    private let externalAccessConfig: ExternalAccessConfig?
    private let agentSettingsContent: AnyView?
    private let meetingsSettingsContent: AnyView?
    private let manageModelsContent: AnyView?

    public struct ExternalAccessConfig {
        public let sidecarPath: String
        public let activityLog: AgentActivityLog
        public let isCLIAvailable: Bool

        public init(
            sidecarPath: String,
            activityLog: AgentActivityLog,
            isCLIAvailable: Bool = true
        ) {
            self.sidecarPath = sidecarPath
            self.activityLog = activityLog
            self.isCLIAvailable = isCLIAvailable
        }
    }

    public init(
        cloudKitEnabled: Bool,
        containerIdentifier: String,
        aiRouter: AIRouter? = nil,
        notificationsAuthorized: Bool? = nil,
        quietHoursStartTime: Binding<Date>? = nil,
        quietHoursEndTime: Binding<Date>? = nil,
        externalAccessConfig: ExternalAccessConfig? = nil,
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
        self.externalAccessConfig = externalAccessConfig
        self.agentSettingsContent = agentSettingsContent
        self.meetingsSettingsContent = meetingsSettingsContent
        self.manageModelsContent = manageModelsContent
        self.onExportRequested = onExportRequested
        _liveData = State(initialValue: aiRouter.map(AISettingsLiveData.init(router:)))
    }

    public var body: some View {
        #if os(macOS)
        ZStack {
            NexusWallpaper()
            macSettingsScroll
        }
        .background(NexusColor.Background.base)
        .frame(minWidth: 620, minHeight: 520)
        #else
        settingsForm
        #endif
    }

    #if os(macOS)
    private var macSettingsScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                macSettingsContent
            }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
            .padding(.top, 34)
            .padding(.bottom, 48)
        }
        .scrollContentBackground(.hidden)
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

    @ViewBuilder
    private var macSettingsContent: some View {
        macGeneralSection
        macSyncSection
        macTasksSection
        macProvidersSection
        macVoiceSection
        macNavigationSection(
            title: "Modele",
            label: "Manage Models",
            systemImage: "cpu",
            destination: manageModelsContent,
            footer: "Pobrane modele lokalne, przypisanie czatu/embeddera, pamięć i zwalnianie zasobów."
        )
        macNavigationSection(
            title: "Agent",
            label: "Agent",
            systemImage: "sparkles",
            destination: agentSettingsContent,
            footer: "Pamięć agenta, indeksowanie, harmonogramy, audyt i routing dostawców."
        )
        macNavigationSection(
            title: "Spotkania",
            label: "Spotkania",
            systemImage: "person.wave.2",
            destination: meetingsSettingsContent,
            footer: "Nagrywanie, transkrypcja, prompty podsumowań, retencja i importy."
        )
        if advancedEnabled, let config = externalAccessConfig {
            ExternalAccessSection(
                sidecarPath: config.sidecarPath,
                activityLog: config.activityLog,
                isClaudeCLIAvailable: config.isCLIAvailable
            )
        }
        macAdvancedSection
        macAboutSection
    }

    private var macGeneralSection: some View {
        macSettingsSection("Ogólne") {
            VStack(spacing: 0) {
                macSettingsRow("Motyw") {
                    Picker("Motyw", selection: $theme) {
                        ForEach(NexusTheme.allCases, id: \.rawValue) { value in
                            Text(label(for: value)).tag(value.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 142)
                }
                macDivider()
                macHelperText("Tryb jasny pojawi się po ustabilizowaniu bazowych tokenów.")
                macDivider()
                macSettingsRow("Pokaż zaawansowane funkcje") {
                    Toggle("", isOn: $advancedEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                macDivider()
                macHelperText("Odsłania dostęp zewnętrzny i zaawansowane ustawienia dostawców chmurowych.")
            }
        }
    }

    private var macSyncSection: some View {
        macSettingsSection("Synchronizacja") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: cloudKitEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(cloudKitEnabled ? NexusColor.Text.tertiary : NexusColor.Text.secondary)
                    .frame(width: 18, alignment: .center)
                VStack(alignment: .leading, spacing: 8) {
                    Text(cloudKitEnabled ? "iCloud aktywny" : "iCloud niedostępny")
                        .font(NexusType.bodySmall.weight(.semibold))
                        .foregroundStyle(NexusColor.Text.primary)
                    Text(containerIdentifier)
                        .font(NexusType.mono)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(cloudKitEnabled ? "Prywatna baza CloudKit jest włączona." : "Wyłączone w lokalnym środowisku deweloperskim.")
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .fill(NexusColor.Background.raised.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var macTasksSection: some View {
        if let config = tasksConfig {
            macSettingsSection(
                "Zadania",
                footer: "Nexus czyta wydarzenia z systemowego Kalendarza w trybie tylko do odczytu. Nic nie tworzy ani nie modyfikuje."
            ) {
                VStack(spacing: 0) {
                    if !config.authorized {
                        deniedBanner
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        macDivider()
                    }
                    macSettingsRow("Cisza nocna od") {
                        DatePicker("", selection: config.start, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 102)
                    }
                    macDivider()
                    macSettingsRow("Cisza nocna do") {
                        DatePicker("", selection: config.end, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 102)
                    }
                    macDivider()
                    macSettingsRow("Pokaż wydarzenia z Kalendarza w Today") {
                        Toggle("", isOn: $calendarEventsInTodayEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: calendarEventsInTodayEnabled) { _, newValue in
                                handleCalendarToggleChange(newValue)
                            }
                    }
                    macDivider()
                    if calendarPermission.status == .denied || calendarPermission.status == .restricted {
                        macCalendarDeniedRow
                        macDivider()
                    }
                    macSettingsRow("Uprawnienia Kalendarza") {
                        HStack(spacing: 12) {
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

    private var macCalendarDeniedRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NexusColor.Text.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Dostęp do Kalendarza wyłączony")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                Text("Włącz uprawnienia w Ustawieniach systemowych, aby zobaczyć wydarzenia w Today.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
            Spacer(minLength: 8)
            openCalendarSettingsButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var macProvidersSection: some View {
        macSettingsSection("On-device providers", footer: "Phase 1l-MLX adds a local LLM for longer-context work.") {
            VStack(spacing: 0) {
                macProviderRow(
                    title: "Apple Intelligence",
                    subtitle: "Local generation",
                    state: liveData?.appleIntelligenceAvailability ?? .unavailable(reason: .modelNotAvailable)
                )
                macDivider()
                macProviderRow(
                    title: "Embeddings",
                    subtitle: "NLEmbedding semantic index",
                    state: liveData?.embeddingAvailability ?? .unavailable(reason: .modelNotAvailable)
                )
            }
        }
    }

    private var macVoiceSection: some View {
        macSettingsSection("Voice") {
            VStack(spacing: 0) {
                macProviderRow(
                    title: "Transcription",
                    subtitle: "WhisperKit local speech-to-text",
                    state: liveData?.whisperKitAvailability ?? .unavailable(reason: .modelNotAvailable)
                )
                macDivider()
                macSettingsRow("Preload transcription model at launch") {
                    WhisperKitPreloadToggle()
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    @ViewBuilder
    private func macNavigationSection(
        title: String,
        label: String,
        systemImage: String,
        destination: AnyView?,
        footer: String
    ) -> some View {
        if let destination {
            macSettingsSection(title, footer: footer) {
                NavigationLink {
                    destination
                } label: {
                    HStack(spacing: 12) {
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var macAdvancedSection: some View {
        macSettingsSection("Advanced") {
            Button(action: onExportRequested) {
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 18)
                    Text("Export to Folder...")
                        .font(NexusType.bodySmall.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(NexusColor.Text.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
    }

    private var macAboutSection: some View {
        macSettingsSection("About") {
            VStack(spacing: 0) {
                macReadOnlyRow("Nexus", value: bundleShortVersion)
                macDivider()
                macReadOnlyRow("Build", value: bundleVersion)
                macDivider()
                macReadOnlyRow("Core", value: NexusCore.version)
            }
        }
    }

    private func macProviderRow(title: String, subtitle: String, state: AvailabilityState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(NexusType.bodySmall.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                Text(subtitle)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            Spacer(minLength: 16)
            switch state {
            case .available:
                NexusBadge("Local", systemImage: "checkmark.circle.fill", tone: .pos)
            case .unavailable(let reason):
                NexusBadge(reasonLabel(reason), systemImage: "exclamationmark.circle", tone: .warn)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func macReadOnlyRow(_ title: String, value: String) -> some View {
        macSettingsRow(title) {
            Text(value)
                .font(NexusType.bodySmall.weight(.medium))
                .foregroundStyle(NexusColor.Text.secondary)
        }
    }

    private func macSettingsSection<Content: View>(
        _ title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            nexusSettingsSectionHeader(title)
            macSettingsCard {
                content()
            }
            if let footer {
                Text(footer)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func macSettingsCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .fill(NexusColor.Background.raised.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
    }

    private func macSettingsRow<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .font(NexusType.bodySmall.weight(.medium))
                .foregroundStyle(NexusColor.Text.primary)
            Spacer(minLength: 16)
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func macHelperText(_ text: String) -> some View {
        Text(text)
            .font(NexusType.caption)
            .foregroundStyle(NexusColor.Text.muted)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macDivider() -> some View {
        Rectangle()
            .fill(NexusColor.Line.hairline)
            .frame(height: 1)
            .padding(.horizontal, 16)
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
        case .amberDark: return "Ciemny"
        }
    }

    private func reasonLabel(_ reason: AvailabilityState.UnavailableReason) -> String {
        switch reason {
        case .modelNotAvailable: return "Not available on this device"
        case .modelDownloading: return "Downloading..."
        case .userDisabled: return "Disabled in System Settings"
        }
    }

    private var bundleShortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    private var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
    #endif

    private var settingsForm: some View {
        Form {
            settingsContent
        }
        .formStyle(.grouped)
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
    }

    @ViewBuilder
    private var settingsContent: some View {
        GeneralSettingsSection()
        SyncSettingsSection(
            cloudKitEnabled: cloudKitEnabled,
            containerIdentifier: containerIdentifier
        )
        tasksSection
        #if os(iOS)
        AppleWatchSettingsSection()
        #endif
        AISettingsSection(liveData: liveData)
        manageModelsSection
        agentSettingsSection
        meetingsSettingsSection
        externalAccessSection
        AdvancedSettingsSection(onExportRequested: onExportRequested)
        AboutSettingsSection()
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
    private var tasksSection: some View {
        if let config = tasksConfig {
            Section {
                if !config.authorized {
                    deniedBanner
                }
                DatePicker(
                    "Cisza nocna od",
                    selection: config.start,
                    displayedComponents: .hourAndMinute
                )
                DatePicker(
                    "Cisza nocna do",
                    selection: config.end,
                    displayedComponents: .hourAndMinute
                )
                calendarSettingsArea
            } header: {
                nexusSettingsSectionHeader("Zadania")
            } footer: {
                Text("Nexus czyta wydarzenia z systemowego Kalendarza w trybie tylko do odczytu. Nic nie tworzy ani nie modyfikuje.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
        }
    }

    @ViewBuilder
    private var calendarSettingsArea: some View {
        Toggle("Pokaż wydarzenia z Kalendarza w Today", isOn: $calendarEventsInTodayEnabled)
            .onChange(of: calendarEventsInTodayEnabled) { _, newValue in
                guard newValue else { return }
                switch calendarPermission.status {
                case .notDetermined:
                    Task { await calendarPermission.requestAccess() }
                case .denied, .restricted:
                    // The toggle would silently lie — flip it back and surface the gate.
                    calendarEventsInTodayEnabled = false
                case .fullAccess, .writeOnly:
                    break
                }
            }

        if calendarPermission.status == .denied || calendarPermission.status == .restricted {
            NexusCard(.elev2, padding: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    // §3: the `exclamationmark.triangle.fill` glyph shape
                    // carries the warning semantic, so the hue is dropped
                    // — achromatic `NexusColor.Text.secondary` (§2
                    // LabPalette.read), state carried by shape not color.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NexusColor.Text.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dostęp do Kalendarza wyłączony")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NexusColor.Text.primary)
                        Text("Włącz uprawnienia w Ustawieniach systemowych, aby zobaczyć wydarzenia w Today.")
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.muted)
                    }
                    Spacer(minLength: 8)
                    openCalendarSettingsButton
                }
            }
        }

        inlineStatusCard {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Uprawnienia Kalendarza")
                    .font(NexusType.bodySmall.weight(.medium))
                    .foregroundStyle(NexusColor.Text.secondary)
                Spacer(minLength: 12)
                calendarPermissionStatusLabel
                    .font(NexusType.bodySmall.weight(.medium))

                if calendarPermission.status == .denied || calendarPermission.status == .restricted {
                    openCalendarSettingsButton
                }
            }
        }
    }

    private func inlineStatusCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .fill(NexusColor.Background.raised.opacity(0.42))
            )
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var openCalendarSettingsButton: some View {
        #if os(macOS)
        Button("Otwórz Ustawienia", action: openCalendarSettings)
            .buttonStyle(.link)
        #else
        Button("Otwórz Ustawienia", action: openCalendarSettings)
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
            Text("Nie pytano")
                .foregroundStyle(NexusColor.Text.muted)
        case .denied:
            Text("Odmówiono")
                .foregroundStyle(NexusColor.Text.primary)
        case .restricted:
            Text("Ograniczony")
                .foregroundStyle(NexusColor.Text.primary)
        case .fullAccess:
            Text("Przyznany")
                .foregroundStyle(NexusColor.Text.secondary)
        case .writeOnly:
            Text("Tylko zapis")
                .foregroundStyle(NexusColor.Text.muted)
        }
    }

    @ViewBuilder
    private var externalAccessSection: some View {
        if advancedEnabled {
            #if os(macOS)
            if let config = externalAccessConfig {
                ExternalAccessSection(
                    sidecarPath: config.sidecarPath,
                    activityLog: config.activityLog,
                    isClaudeCLIAvailable: config.isCLIAvailable
                )
            }
            #elseif os(iOS)
            ExternalAccessInfoSection()
            #endif
        }
    }

    @ViewBuilder
    private var manageModelsSection: some View {
        if let manageModelsContent {
            Section {
                NavigationLink {
                    manageModelsContent
                } label: {
                    Label("Manage Models", systemImage: "cpu")
                }
            } header: {
                nexusSettingsSectionHeader("Modele")
            } footer: {
                Text("Pobrane modele lokalne, przypisanie czatu/embeddera, pamięć i zwalnianie zasobów.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
        }
    }

    @ViewBuilder
    private var agentSettingsSection: some View {
        if let agentSettingsContent {
            Section {
                NavigationLink {
                    agentSettingsContent
                } label: {
                    Label("Agent", systemImage: "sparkles")
                }
            } header: {
                nexusSettingsSectionHeader("Agent")
            } footer: {
                Text("Pamięć agenta, indeksowanie, harmonogramy, audyt i routing dostawców.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
        }
    }

    @ViewBuilder
    private var meetingsSettingsSection: some View {
        if let meetingsSettingsContent {
            Section {
                NavigationLink {
                    meetingsSettingsContent
                } label: {
                    Label("Spotkania", systemImage: "person.wave.2")
                }
            } header: {
                nexusSettingsSectionHeader("Spotkania")
            } footer: {
                Text("Nagrywanie, transkrypcja, prompty podsumowań, retencja i importy.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
        }
    }

    @ViewBuilder
    private var deniedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            // §3 emphasis row: hue removed; the `bell.slash.fill` glyph
            // shape already carries the negative semantic, and the
            // heavier Geist weight + `Text.primary` ink step (§2
            // LabPalette.ink) restore the lost salience without color.
            Label("Notyfikacje wyłączone", systemImage: "bell.slash.fill")
                .foregroundStyle(NexusColor.Text.primary)
                .font(.subheadline.weight(.bold))
            Button("Otwórz Ustawienia systemowe", action: openSystemSettings)
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

@ViewBuilder
func nexusSettingsSectionHeader(_ title: String) -> some View {
    // Oracle `SettingsPreview.group(_:)`: `GeistMono-SemiBold` 10 /
    // tracking 1.8 / §2 `faint` → `NexusColor.Text.muted`. §8 raw
    // `Font.custom` reuse is the locked stopgap when the oracle weight
    // is not a `NexusType` token (MP-2/MP-3 precedent).
    Text(title.uppercased())
        .font(Font.custom("GeistMono-SemiBold", size: 10))
        .tracking(1.8)
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
