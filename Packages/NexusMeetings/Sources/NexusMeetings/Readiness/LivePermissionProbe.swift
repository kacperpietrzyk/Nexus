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
