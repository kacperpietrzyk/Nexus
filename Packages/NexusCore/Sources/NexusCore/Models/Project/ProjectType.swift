import Foundation

/// High-level kind of a `Project` (Projects tier — universal types extension).
/// Stored on `Project.typeRaw` as `String` (SwiftData + CloudKit reject enum-typed
/// properties). Raw values are CloudKit-bound and MUST NEVER be renamed without a
/// migration. Drives the stage preset (`stages`), default sections, and which fields
/// the UI surfaces. Existing/pre-V15 projects read back as `.generic`.
public enum ProjectType: String, Codable, Sendable, CaseIterable {
    case implementation
    case sales
    case audit
    case internalDev  // `internal` is a Swift keyword
    case generic  // fallback + all pre-V15 projects

    public var displayName: String {
        switch self {
        case .implementation: return "Implementation"
        case .sales: return "Sales"
        case .audit: return "Audit"
        case .internalDev: return "Internal / Dev"
        case .generic: return "Project"
        }
    }
}
