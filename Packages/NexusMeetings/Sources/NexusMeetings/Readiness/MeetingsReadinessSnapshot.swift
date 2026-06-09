import Foundation

public enum PermissionState: String, Codable, Sendable, Equatable {
    case granted
    case denied
    case notDetermined
    case unsupported
    case unknown
}

public enum MeetingsModelID: String, Codable, Sendable, CaseIterable, Equatable {
    case parakeet
    case sortformer
    case whisperKit
}

public enum ModelDownloadState: Codable, Sendable, Equatable {
    case absent
    case downloading(fraction: Double?)
    case ready
    case failed(reason: String)
}

public struct ModelReadiness: Codable, Sendable, Equatable {
    public let id: MeetingsModelID
    public let downloaded: Bool
    public let sizeBytes: Int64?
    public let state: ModelDownloadState

    public init(id: MeetingsModelID, downloaded: Bool, sizeBytes: Int64?, state: ModelDownloadState) {
        self.id = id
        self.downloaded = downloaded
        self.sizeBytes = sizeBytes
        self.state = state
    }
}

public struct MeetingsPermissionsReadiness: Codable, Sendable, Equatable {
    public let microphone: PermissionState
    public let accessibility: PermissionState
    public let audioCapture: PermissionState

    public init(
        microphone: PermissionState,
        accessibility: PermissionState,
        audioCapture: PermissionState
    ) {
        self.microphone = microphone
        self.accessibility = accessibility
        self.audioCapture = audioCapture
    }
}

public struct MeetingsEnvironmentReadiness: Codable, Sendable, Equatable {
    public let macOSCompatible: Bool
    public let autoRecordEnabled: Bool

    public init(macOSCompatible: Bool, autoRecordEnabled: Bool) {
        self.macOSCompatible = macOSCompatible
        self.autoRecordEnabled = autoRecordEnabled
    }
}

public struct MeetingsReadinessSnapshot: Codable, Sendable, Equatable {
    public let permissions: MeetingsPermissionsReadiness
    public let models: [ModelReadiness]
    public let environment: MeetingsEnvironmentReadiness
    public let lastUpdated: Date

    public init(
        permissions: MeetingsPermissionsReadiness,
        models: [ModelReadiness],
        environment: MeetingsEnvironmentReadiness,
        lastUpdated: Date
    ) {
        self.permissions = permissions
        self.models = models
        self.environment = environment
        self.lastUpdated = lastUpdated
    }
}
