import Foundation
import Testing

@testable import NexusCore

@Suite("ProjectStatus")
struct ProjectStatusTests {
    /// Raw values are CloudKit-bound — a rename silently corrupts persistence.
    /// Note `cancelled` is British (two `l`s), distinct from `WorkflowState.canceled`.
    @Test("raw values are stable")
    func rawValues() {
        #expect(ProjectStatus.backlog.rawValue == "backlog")
        #expect(ProjectStatus.planned.rawValue == "planned")
        #expect(ProjectStatus.active.rawValue == "active")
        #expect(ProjectStatus.inReview.rawValue == "inReview")
        #expect(ProjectStatus.completed.rawValue == "completed")
        #expect(ProjectStatus.cancelled.rawValue == "cancelled")
    }

    @Test("all cases are covered")
    func allCases() {
        #expect(ProjectStatus.allCases.count == 6)
    }

    @Test("Codable round-trips")
    func codable() throws {
        for status in ProjectStatus.allCases {
            let encoded = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(ProjectStatus.self, from: encoded)
            #expect(decoded == status)
        }
    }

    @MainActor
    @Test("Project defaults to backlog and exposes a computed status")
    func projectDefault() {
        let project = Project(name: "ThreatForge")
        #expect(project.statusRaw == ProjectStatus.backlog.rawValue)
        #expect(project.status == .backlog)
    }

    @MainActor
    @Test("Project status accessor reflects the stored raw and falls back to backlog")
    func projectAccessor() {
        let project = Project(name: "Vanguard", status: .active)
        #expect(project.status == .active)
        project.statusRaw = "not-a-real-status"
        #expect(project.status == .backlog)
    }
}
