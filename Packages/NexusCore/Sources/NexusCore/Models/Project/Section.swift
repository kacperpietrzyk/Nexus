import Foundation
import SwiftData

/// Project section (a sub-grouping within a `Project`).
///
/// - Warning: `NexusCore.Section` shares its bare name with `SwiftUI.Section`.
///   Inside a file that imports both `NexusCore` and `SwiftUI`, refer to this
///   type via the `ProjectSection` typealias exported by `TasksFeature` (or
///   spell it out as `NexusCore.Section`). Renaming the model is intentionally
///   avoided because it would force a SwiftData schema migration.
@Model
public final class Section: Searchable {
    public var id: UUID = UUID()
    public var kind: ItemKind = ItemKind.section
    public var projectID: UUID = UUID()
    public var name: String = ""
    public var orderIndex: Double = 0.0
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        name: String,
        orderIndex: Double = 0.0
    ) {
        self.id = id
        self.kind = .section
        self.projectID = projectID
        self.name = name
        self.orderIndex = orderIndex
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }

    public var title: String {
        get { name }
        set { name = newValue }
    }

    public var searchableText: String { name }
}
