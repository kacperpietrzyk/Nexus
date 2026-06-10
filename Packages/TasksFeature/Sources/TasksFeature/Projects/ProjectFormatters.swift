import Foundation

/// Shared date formatters for the Liquid Projects surfaces.
/// English UI rule: explicit en_US (system locale may be pl_PL).
/// `@MainActor` because `DateFormatter` is not Sendable and every caller is
/// SwiftUI view code (`ProjectKanban` cards, `ProjectTaskTable` Due column,
/// `ProjectInspector` risk anchors).
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
}
