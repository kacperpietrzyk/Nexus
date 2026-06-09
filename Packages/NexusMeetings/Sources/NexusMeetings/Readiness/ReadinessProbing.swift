import Foundation

public protocol PermissionProbing: Sendable {
    func currentPermissions() -> MeetingsPermissionsReadiness
}

public protocol ModelProbing: Sendable {
    func currentModels() -> [ModelReadiness]
}

public protocol EnvironmentProbing: Sendable {
    func currentEnvironment() -> MeetingsEnvironmentReadiness
}

public struct MeetingsReadinessComputer: Sendable {
    private let permissions: any PermissionProbing
    private let models: any ModelProbing
    private let environment: any EnvironmentProbing
    private let clock: @Sendable () -> Date

    public init(
        permissions: any PermissionProbing,
        models: any ModelProbing,
        environment: any EnvironmentProbing,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.permissions = permissions
        self.models = models
        self.environment = environment
        self.clock = clock
    }

    public func snapshot() -> MeetingsReadinessSnapshot {
        MeetingsReadinessSnapshot(
            permissions: permissions.currentPermissions(),
            models: models.currentModels(),
            environment: environment.currentEnvironment(),
            lastUpdated: clock()
        )
    }
}
