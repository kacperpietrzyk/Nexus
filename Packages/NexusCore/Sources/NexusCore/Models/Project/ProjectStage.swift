import Foundation

/// Granular position within a `ProjectType`'s preset pipeline (universal types
/// extension). Stored on `Project.stageRaw` as `String`; raw values are CloudKit-bound
/// and MUST NEVER be renamed without a migration. A single flat namespace (cases are
/// grouped per type via `ProjectType.stages`) keeps one stable raw vocabulary.
///
/// Orthogonal-but-synced with `ProjectStatus`: `coarseStatus` maps each stage to the
/// universal lifecycle so cross-type filters/roadmap keep working. Setting a stage
/// derives the status (see `ProjectRepository.setStage`).
public enum ProjectStage: String, Codable, Sendable, CaseIterable {
    // implementation
    case kickoff, deliveryDocs, softwareDelivery, installation, asBuiltDocs, acceptance, training, support, closed
    // sales
    case lead, qualifying, proposal, tender, won, lost
    // audit
    case auditPlan, auditExecution, auditReport
    // internalDev
    case planning, building, reviewing, shipped

    public var displayName: String {
        switch self {
        case .kickoff: return "Kick-off"
        case .deliveryDocs: return "Implementation Docs"
        case .softwareDelivery: return "Software Delivery"
        case .installation: return "Installation"
        case .asBuiltDocs: return "As-Built Docs"
        case .acceptance: return "Acceptance"
        case .training: return "Training"
        case .support: return "Support"
        case .closed: return "Closed"
        case .lead: return "Lead"
        case .qualifying: return "Qualifying"
        case .proposal: return "Proposal"
        case .tender: return "Tender"
        case .won: return "Won"
        case .lost: return "Lost"
        case .auditPlan: return "Audit Plan"
        case .auditExecution: return "Audit Execution"
        case .auditReport: return "Audit Report"
        case .planning: return "Planning"
        case .building: return "Building"
        case .reviewing: return "Reviewing"
        case .shipped: return "Shipped"
        }
    }

    /// Maps each granular stage to the coarse `ProjectStatus` so cross-type views
    /// (filters, roadmap, health) keep working unchanged. Note `cancelled` keeps the
    /// British two-`l` spelling (matches `ProjectStatus`).
    public var coarseStatus: ProjectStatus {
        switch self {
        case .lead, .qualifying, .auditPlan, .planning:
            return .planned
        case .proposal, .tender, .kickoff, .deliveryDocs, .softwareDelivery,
             .installation, .asBuiltDocs, .auditExecution, .building, .reviewing,
             .support, .training, .acceptance:
            return .active
        case .won, .auditReport, .shipped, .closed:
            return .completed
        case .lost:
            return .cancelled
        }
    }
}

extension ProjectType {
    /// Ordered stage preset for this type. `.generic` has no granular pipeline
    /// (uses `ProjectStatus` only) and returns `[]`.
    public var stages: [ProjectStage] {
        switch self {
        case .implementation:
            return [.kickoff, .deliveryDocs, .softwareDelivery, .installation, .asBuiltDocs, .acceptance, .training, .support, .closed]
        case .sales:
            return [.lead, .qualifying, .proposal, .tender, .won, .lost]
        case .audit:
            return [.auditPlan, .auditExecution, .auditReport]
        case .internalDev:
            return [.planning, .building, .reviewing, .shipped]
        case .generic:
            return []
        }
    }
}
