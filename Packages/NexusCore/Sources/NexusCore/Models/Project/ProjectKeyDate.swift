import Foundation
import SwiftData

/// A named contract/lifecycle anchor date on a `Project` (universal-types extension):
/// e.g. T0 (contract signing), PO (acceptance protocol), kick-off, decision date.
/// Stored as a real `Date` (not a `customFields` string) so the roadmap and
/// deadline-risk surfaces can query it. Addressed purely by `projectID` — it is never
/// a `Link` graph endpoint, so it intentionally has NO `ItemKind` case.
///
/// Synced (CloudKit `.private`) ⇒ every stored property is defaulted. Soft-delete via
/// `deletedAt`. Business-day (DR) offset computation is out of scope for v1.
@Model
public final class ProjectKeyDate {
    public var id: UUID = UUID()
    public var projectID: UUID = UUID()
    /// Stable anchor key ("T0", "PO", "kickoff", "decision").
    public var anchorKey: String = ""
    /// Human label, e.g. "Podpisanie umowy".
    public var label: String = ""
    public var date: Date = Date.now
    /// Contractual (DR-bound) deadline vs an estimate.
    public var isContractual: Bool = false
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        anchorKey: String,
        label: String,
        date: Date,
        isContractual: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.anchorKey = anchorKey
        self.label = label
        self.date = date
        self.isContractual = isContractual
        let now = Date.now
        self.createdAt = now
        self.updatedAt = now
        self.deletedAt = nil
    }
}
