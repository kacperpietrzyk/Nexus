import AVFoundation
import Foundation
import Testing

@testable import NexusMeetings

@Suite("LivePermissionProbe")
struct LivePermissionProbeTests {
    @Test("maps raw AV authorization + AX trust + consent flag into PermissionState")
    func mapping() {
        let probe = LivePermissionProbe(
            microphoneStatus: { .denied },
            accessibilityTrusted: { true },
            audioCaptureConsent: { .granted }
        )
        let permissions = probe.currentPermissions()
        #expect(permissions.microphone == .denied)
        #expect(permissions.accessibility == .granted)
        #expect(permissions.audioCapture == .granted)
    }

    @Test("notDetermined mic and untrusted AX map correctly")
    func notDetermined() {
        let probe = LivePermissionProbe(
            microphoneStatus: { .notDetermined },
            accessibilityTrusted: { false },
            audioCaptureConsent: { .unknown }
        )
        let permissions = probe.currentPermissions()
        #expect(permissions.microphone == .notDetermined)
        #expect(permissions.accessibility == .denied)
        #expect(permissions.audioCapture == .unknown)
    }
}
