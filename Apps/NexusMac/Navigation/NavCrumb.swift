// Shell navigation value types: breadcrumb segment + deep-link target.
//
// These are the cross-task vocabulary for the macOS navigation-unification
// pass: every destination produces a `NavCrumb` for the breadcrumb bar and
// consumes a `DeepLinkTarget` to open a specific detail item.

import Foundation

/// One segment of the shell breadcrumb trail.
struct NavCrumb: Identifiable, Equatable {
    /// `"root"` for the destination crumb, or the detail item's token for a leaf.
    let id: String
    /// Display label (e.g. "Tasks", or a project's name).
    let label: String
    /// `true` for the current page — rendered non-interactive (no back-link).
    let isLeaf: Bool
}

/// A request to open a specific detail item within a destination.
///
/// `token`/`init?(token:)` give a stable round-trip so a deep link can be
/// encoded into `NavLocation.detailToken` and re-resolved on back/forward.
enum DeepLinkTarget: Equatable {
    case project(UUID)
    case savedFilter(UUID)
    case meeting(UUID)
    case note(UUID)
    case person(UUID)

    /// Stable `"<kind>:<uuid>"` token for `NavLocation.detailToken`.
    var token: String {
        switch self {
        case .project(let id): return "project:\(id.uuidString)"
        case .savedFilter(let id): return "savedFilter:\(id.uuidString)"
        case .meeting(let id): return "meeting:\(id.uuidString)"
        case .note(let id): return "note:\(id.uuidString)"
        case .person(let id): return "person:\(id.uuidString)"
        }
    }

    /// Inverse of `token`. Returns `nil` for an unrecognized or malformed token.
    init?(token: String) {
        guard let separator = token.firstIndex(of: ":") else { return nil }
        let kind = String(token[token.startIndex..<separator])
        let rawID = String(token[token.index(after: separator)...])
        guard let id = UUID(uuidString: rawID) else { return nil }
        switch kind {
        case "project": self = .project(id)
        case "savedFilter": self = .savedFilter(id)
        case "meeting": self = .meeting(id)
        case "note": self = .note(id)
        case "person": self = .person(id)
        default: return nil
        }
    }
}
