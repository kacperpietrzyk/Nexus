import AVFoundation
import Foundation
import NexusCore

#if canImport(ApplicationServices)
import ApplicationServices
#endif

public struct LivePermissionProbe: PermissionProbing {
    private let microphoneStatus: @Sendable () -> AVAuthorizationStatus
    private let accessibilityTrusted: @Sendable () -> Bool
    private let audioCaptureConsent: @Sendable () -> PermissionState

    public init(
        microphoneStatus: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .audio)
        },
        accessibilityTrusted: @escaping @Sendable () -> Bool = { Self.systemAccessibilityTrusted() },
        audioCaptureConsent: @escaping @Sendable () -> PermissionState = {
            AudioCaptureConsentStore.shared.state()
        }
    ) {
        self.microphoneStatus = microphoneStatus
        self.accessibilityTrusted = accessibilityTrusted
        self.audioCaptureConsent = audioCaptureConsent
    }

    public func currentPermissions() -> MeetingsPermissionsReadiness {
        MeetingsPermissionsReadiness(
            microphone: Self.map(microphoneStatus()),
            accessibility: accessibilityTrusted() ? .granted : .denied,
            audioCapture: audioCaptureConsent()
        )
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    @usableFromInline
    static func systemAccessibilityTrusted() -> Bool {
        #if canImport(ApplicationServices)
        return AXIsProcessTrusted()
        #else
        return false
        #endif
    }
}

public struct AccessibilityPromptGate {
    private let isTrusted: () -> Bool
    private let hasPrompted: () -> Bool
    private let markPrompted: () -> Void
    private let prompt: () -> Void

    public init(
        isTrusted: @escaping () -> Bool = { LivePermissionProbe.systemAccessibilityTrusted() },
        hasPrompted: @escaping () -> Bool = {
            UserDefaults.nexusGroup.bool(forKey: "nexus.meetings.ax.didPrompt")
        },
        markPrompted: @escaping () -> Void = {
            UserDefaults.nexusGroup.set(true, forKey: "nexus.meetings.ax.didPrompt")
        },
        prompt: @escaping () -> Void = { LivePermissionProbe.requestAccessibilityPrompt() }
    ) {
        self.isTrusted = isTrusted
        self.hasPrompted = hasPrompted
        self.markPrompted = markPrompted
        self.prompt = prompt
    }

    /// Shows the macOS Accessibility dialog once, only while untrusted.
    public func promptIfNeeded() {
        guard !isTrusted() else { return }
        guard !hasPrompted() else { return }
        markPrompted()
        prompt()
    }
}

extension LivePermissionProbe {
    /// Triggers the system "grant Accessibility" dialog (deep link), unlike the
    /// silent `AXIsProcessTrusted()` used for read-only probing.
    public static func requestAccessibilityPrompt() {
        #if canImport(ApplicationServices)
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        #endif
    }
}

/// Persists the outcome of the most recent system-audio process-tap attempt,
/// since macOS exposes no public authorization-status API for Core Audio taps.
public final class AudioCaptureConsentStore: @unchecked Sendable {
    public static let shared = AudioCaptureConsentStore()

    private let defaults: UserDefaults
    private let key = "nexus.meetings.audioCapture.consent.v1"

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func state() -> PermissionState {
        guard
            let raw = defaults.string(forKey: key),
            let value = PermissionState(rawValue: raw)
        else {
            return .unknown
        }
        return value
    }

    public func record(_ state: PermissionState) {
        defaults.set(state.rawValue, forKey: key)
    }
}
