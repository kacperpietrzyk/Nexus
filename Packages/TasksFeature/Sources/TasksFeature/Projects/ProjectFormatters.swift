import Foundation
import NexusCore

/// Shared date formatters for the Liquid Projects surfaces.
/// English UI rule: explicit en_US (system locale may be pl_PL).
/// `@MainActor` because `DateFormatter` is not Sendable and every caller is
/// SwiftUI view code (`ProjectKanban` cards, `ProjectTaskTable` Due column,
/// `DeliveryRiskCard` risk anchors).
@MainActor
enum ProjectFormatters {

    /// Short "MMM d" day stamp (board card due dates, table Due column,
    /// risk-card anchor dates). `ProjectHeader` keeps its own "MMM d, yyyy"
    /// formatter — the header is the one place the year matters.
    static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Display label for a project's lifecycle status (`ProjectHeader` status
    /// menu, `LiquidProjectScreen` picker rows). Formerly
    /// `ProjectPageView.statusLabel` — relocated here when the superseded
    /// pre-Liquid project page was deleted.
    static func statusLabel(_ status: ProjectStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .planned: return "Planned"
        case .active: return "Active"
        case .inReview: return "In Review"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}
