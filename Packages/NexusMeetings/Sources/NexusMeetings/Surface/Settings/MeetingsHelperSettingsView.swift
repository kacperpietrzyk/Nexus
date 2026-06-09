#if os(macOS) && canImport(ServiceManagement)
import Combine
import NexusUI
@preconcurrency import ServiceManagement
import SwiftUI

public protocol HelperRegistrar: Sendable {
    func register() throws
    func unregister() throws
}

public enum MeetingsHelperService {
    public static let plistName = "com.kacperpietrzyk.nexus.meetings-helper.plist"

    public static var service: SMAppService {
        SMAppService.agent(plistName: plistName)
    }
}

public struct ServiceManagementHelperRegistrar: HelperRegistrar {
    public init() {}

    public func register() throws {
        try MeetingsHelperService.service.register()
    }

    public func unregister() throws {
        try MeetingsHelperService.service.unregister()
    }
}

@MainActor
public final class MeetingsHelperSettingsViewModel: ObservableObject {
    @Published public var isEnabled: Bool
    @Published public var statusLabel: String

    private let statusProvider: () -> SMAppService.Status
    private let registrar: any HelperRegistrar
    private let preferenceStore: any HelperAutoRecordStoring

    public init(
        statusProvider: @escaping () -> SMAppService.Status = {
            MeetingsHelperService.service.status
        },
        registrar: any HelperRegistrar = ServiceManagementHelperRegistrar(),
        preferenceStore: any HelperAutoRecordStoring = UserDefaultsHelperAutoRecordStore.shared
    ) {
        self.statusProvider = statusProvider
        self.registrar = registrar
        self.preferenceStore = preferenceStore

        let status = statusProvider()
        isEnabled = status == .enabled
        statusLabel = Self.describe(status)
    }

    public func refresh() {
        let status = statusProvider()
        isEnabled = status == .enabled
        statusLabel = Self.describe(status)
    }

    public func toggle(enabled: Bool) {
        do {
            if enabled {
                try registrar.register()
            } else {
                try registrar.unregister()
            }
            preferenceStore.save(enabled: enabled)
            if enabled {
                // Kick the (now-launching) helper to prompt for mic + open
                // Accessibility Settings. The helper may still be starting up
                // when this arrives — the readiness panel's [Request] button
                // re-posts if needed.
                DistributedNotificationCenter.default().postNotificationName(
                    MeetingsReadinessNotification.requestPermissions,
                    object: nil, userInfo: nil, deliverImmediately: true
                )
            }
            refresh()
        } catch {
            isEnabled = statusProvider() == .enabled
            statusLabel = "Error: \(error.localizedDescription)"
        }
    }

    public static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:
            "Helper not registered"
        case .enabled:
            "Helper enabled"
        case .requiresApproval:
            "Helper requires approval in System Settings"
        case .notFound:
            "Helper not found"
        @unknown default:
            "Unknown helper status"
        }
    }
}

public struct MeetingsHelperSettingsView: View {
    @ObservedObject private var viewModel: MeetingsHelperSettingsViewModel

    public init(viewModel: MeetingsHelperSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s7) {
            VStack(alignment: .leading, spacing: NexusSpacing.s3) {
                nexusSettingsCardSectionHeader("Helper")
                NexusSettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        NexusSettingsRow("Enable Meetings auto-record") {
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { viewModel.isEnabled },
                                    set: { viewModel.toggle(enabled: $0) }
                                )
                            )
                            .labelsHidden()
                        }
                        Text(viewModel.statusLabel)
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, NexusSpacing.s4)
                            .padding(.bottom, NexusSpacing.s3)
                    }
                }
            }
            MeetingsReadinessSection()
        }
        .onAppear {
            viewModel.refresh()
        }
    }
}
#endif
