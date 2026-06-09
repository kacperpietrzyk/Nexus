import Foundation

public struct LiveEnvironmentProbe: EnvironmentProbing {
    private let autoRecordStore: any HelperAutoRecordStoring
    private let isMacOSCompatible: @Sendable () -> Bool

    public init(
        autoRecordStore: any HelperAutoRecordStoring = UserDefaultsHelperAutoRecordStore.shared,
        isMacOSCompatible: @escaping @Sendable () -> Bool = { Self.systemMacOSCompatible() }
    ) {
        self.autoRecordStore = autoRecordStore
        self.isMacOSCompatible = isMacOSCompatible
    }

    public func currentEnvironment() -> MeetingsEnvironmentReadiness {
        MeetingsEnvironmentReadiness(
            macOSCompatible: isMacOSCompatible(),
            autoRecordEnabled: autoRecordStore.isEnabled()
        )
    }

    @usableFromInline
    static func systemMacOSCompatible() -> Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 14, minorVersion: 4, patchVersion: 0)
        )
    }
}
