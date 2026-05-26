public struct CommandAvailability: Equatable, Sendable {
    public let isEnabled: Bool
    public let disabledReason: String?

    public static let enabled = CommandAvailability(isEnabled: true, disabledReason: nil)

    public static func disabled(reason: String) -> CommandAvailability {
        CommandAvailability(isEnabled: false, disabledReason: reason)
    }
}

public protocol Command: Sendable {
    var id: String { get }
    var title: String { get }
    var subtitle: String? { get }
    var iconName: String { get }
    var keywords: [String] { get }
    var shortcut: [String] { get }
    var availability: CommandAvailability { get async }

    func execute() async throws
}

extension Command {
    public var availability: CommandAvailability {
        get async { .enabled }
    }
}
