import SwiftUI

/// Everything the macOS in-shell Settings needs, assembled in NexusMacApp and injected
/// through the environment. Sub-view thunks keep NexusUI free of upward module deps.
public struct MacSettingsDependencies: @unchecked Sendable {
    public var cloudKitEnabled: Bool
    public var cloudKitContainerIdentifier: String?
    public var notificationsAuthorized: Bool
    public var quietHoursStart: Binding<Date>
    public var quietHoursEnd: Binding<Date>
    public var onExportRequested: () -> Void
    /// Re-skinned composed panels (built by the app, rendered in the detail pane).
    public var manageModelsContent: () -> AnyView
    public var agentSettingsContent: () -> AnyView
    public var meetingsSettingsContent: () -> AnyView
    public var externalAccessContent: () -> AnyView
    public var notesImportContent: () -> AnyView

    public init(
        cloudKitEnabled: Bool,
        cloudKitContainerIdentifier: String?,
        notificationsAuthorized: Bool,
        quietHoursStart: Binding<Date>,
        quietHoursEnd: Binding<Date>,
        onExportRequested: @escaping () -> Void,
        manageModelsContent: @escaping () -> AnyView,
        agentSettingsContent: @escaping () -> AnyView,
        meetingsSettingsContent: @escaping () -> AnyView,
        externalAccessContent: @escaping () -> AnyView,
        notesImportContent: @escaping () -> AnyView = { AnyView(EmptyView()) }
    ) {
        self.cloudKitEnabled = cloudKitEnabled
        self.cloudKitContainerIdentifier = cloudKitContainerIdentifier
        self.notificationsAuthorized = notificationsAuthorized
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.onExportRequested = onExportRequested
        self.manageModelsContent = manageModelsContent
        self.agentSettingsContent = agentSettingsContent
        self.meetingsSettingsContent = meetingsSettingsContent
        self.externalAccessContent = externalAccessContent
        self.notesImportContent = notesImportContent
    }

    /// Inert default so previews / non-injecting hosts compile.
    public static var empty: MacSettingsDependencies {
        MacSettingsDependencies(
            cloudKitEnabled: false,
            cloudKitContainerIdentifier: nil,
            notificationsAuthorized: false,
            quietHoursStart: .constant(.distantPast),
            quietHoursEnd: .constant(.distantPast),
            onExportRequested: {},
            manageModelsContent: { AnyView(EmptyView()) },
            agentSettingsContent: { AnyView(EmptyView()) },
            meetingsSettingsContent: { AnyView(EmptyView()) },
            externalAccessContent: { AnyView(EmptyView()) },
            notesImportContent: { AnyView(EmptyView()) }
        )
    }
}

private struct MacSettingsDependenciesKey: EnvironmentKey {
    static let defaultValue = MacSettingsDependencies.empty
}

extension EnvironmentValues {
    public var macSettingsDependencies: MacSettingsDependencies {
        get { self[MacSettingsDependenciesKey.self] }
        set { self[MacSettingsDependenciesKey.self] = newValue }
    }
}
