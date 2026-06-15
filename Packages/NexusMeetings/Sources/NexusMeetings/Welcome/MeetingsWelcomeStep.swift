#if os(macOS) && canImport(ServiceManagement)
import AVFoundation
import Foundation
import NexusUI
@preconcurrency import ServiceManagement
import SwiftUI

@MainActor
public final class MeetingsWelcomeStepViewModel: ObservableObject {
    @Published public var enableHelper: Bool
    @Published public private(set) var statusText: String?

    private let registrar: any HelperRegistrar
    private let statusProvider: () -> SMAppService.Status
    private let preferenceStore: any HelperAutoRecordStoring
    private let requestMicrophoneAccess: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void

    public init(
        enableHelper: Bool = true,
        registrar: any HelperRegistrar = ServiceManagementHelperRegistrar(),
        statusProvider: @escaping () -> SMAppService.Status = {
            MeetingsHelperService.service.status
        },
        preferenceStore: any HelperAutoRecordStoring =
            UserDefaultsHelperAutoRecordStore.shared,
        requestMicrophoneAccess: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            AVCaptureDevice.requestAccess(for: .audio) { granted in completion(granted) }
        }
    ) {
        self.enableHelper = enableHelper
        self.registrar = registrar
        self.statusProvider = statusProvider
        self.preferenceStore = preferenceStore
        self.requestMicrophoneAccess = requestMicrophoneAccess
    }

    public func refreshStatus() {
        statusText = Self.describe(statusProvider())
    }

    public func skip(onContinue: (Bool) -> Void) {
        preferenceStore.save(enabled: false)
        onContinue(false)
    }

    public func continueFlow(onContinue: (Bool) -> Void) {
        guard enableHelper else {
            preferenceStore.save(enabled: false)
            onContinue(false)
            return
        }

        guard registerHelperIfNeeded() else {
            return
        }

        preferenceStore.save(enabled: true)
        // Request microphone IN-PROCESS — the main app has the `audio-input`
        // entitlement and needs no helper for this. (The previous cross-app
        // `DistributedNotificationCenter` post to the sandboxed helper was
        // unreliable and did nothing on a plain launch.)
        requestMicrophoneAccess { _ in }
        // Nudge the (now-launching) helper to refresh its Accessibility/system-
        // audio view as a fallback; the in-process readiness panel is what
        // actually shows status.
        // TODO: prefer the helper's XPC interface once it vends a permission entry
        // point (connecting via XPC also launches the agent on demand).
        DistributedNotificationCenter.default().postNotificationName(
            MeetingsReadinessNotification.refreshReadiness,
            object: nil, userInfo: nil, deliverImmediately: true
        )
        onContinue(true)
    }

    private func registerHelperIfNeeded() -> Bool {
        let status = statusProvider()
        switch status {
        case .notRegistered:
            do {
                try registrar.register()
                statusText = Self.describe(statusProvider())
                return true
            } catch {
                statusText = "Helper registration failed: \(error.localizedDescription)"
                return false
            }
        case .enabled, .requiresApproval:
            statusText = Self.describe(status)
            return true
        case .notFound:
            statusText = Self.describe(status)
            return false
        @unknown default:
            statusText = Self.describe(status)
            return false
        }
    }

    private static func describe(_ status: SMAppService.Status) -> String {
        switch status {
        case .notRegistered:
            "Helper is not registered yet."
        case .enabled:
            "Helper is enabled."
        case .requiresApproval:
            "Helper requires approval in System Settings."
        case .notFound:
            "Helper was not found in this build."
        @unknown default:
            "Helper status is unknown."
        }
    }
}

public struct MeetingsWelcomeStep: View {
    @StateObject private var viewModel: MeetingsWelcomeStepViewModel

    private let onContinue: (Bool) -> Void

    public init(
        onContinue: @escaping (Bool) -> Void,
        registrar: any HelperRegistrar = ServiceManagementHelperRegistrar(),
        statusProvider: @escaping () -> SMAppService.Status = {
            MeetingsHelperService.service.status
        },
        preferenceStore: any HelperAutoRecordStoring =
            UserDefaultsHelperAutoRecordStore.shared
    ) {
        _viewModel = StateObject(
            wrappedValue: MeetingsWelcomeStepViewModel(
                registrar: registrar,
                statusProvider: statusProvider,
                preferenceStore: preferenceStore
            )
        )
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 32)

            // MP-6.3 mechanical zero-ref scaffold repoint (Accent.solid ≡ Text.primary,
            // 0xF2F2F4). NexusMeetings is out-of-AUDIT-scope (no LabKit redesign owed);
            // this is the token-delete mechanic only, NOT a design decision.
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(NexusColor.Text.primary)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Meetings auto-record")
                    .font(NexusType.h1)
                    .foregroundStyle(NexusColor.Text.primary)

                Text(copy)
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }

            NexusCard(.elev2, padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    NexusToggle(
                        "Enable Meetings auto-record",
                        caption: "Nexus will keep the helper available for Zoom, Teams, and Meet detection.",
                        isOn: $viewModel.enableHelper
                    )

                    if let statusText = viewModel.statusText {
                        Text(statusText)
                            .font(NexusType.meta)
                            .foregroundStyle(NexusColor.Text.secondary)
                    }
                }
            }
            .frame(maxWidth: 460)

            HStack(spacing: 12) {
                NexusButton(variant: .outline, size: .lg, action: skip) {
                    Text("Skip")
                        .frame(width: 132)
                }

                NexusButton(variant: .primary, size: .lg, action: continueFlow) {
                    Text("Continue")
                        .frame(width: 132)
                }
                .keyboardShortcut(.defaultAction)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
        .onAppear {
            viewModel.refreshStatus()
        }
    }

    private var copy: String {
        """
        Nexus can detect meetings as you join them, then prepare transcripts, summaries, and action items. \
        You can disable this later in Settings -> Meetings.
        """
    }

    private func skip() {
        viewModel.skip(onContinue: onContinue)
    }

    private func continueFlow() {
        viewModel.continueFlow(onContinue: onContinue)
    }
}
#endif
