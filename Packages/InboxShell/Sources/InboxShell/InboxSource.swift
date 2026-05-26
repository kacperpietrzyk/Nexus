import Foundation

public protocol InboxSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    var iconName: String { get }

    func items() async throws -> [InboxItem]
    func archive(_ item: InboxItem) async throws
    func snooze(_ item: InboxItem, until date: Date) async throws
}
