import Foundation

/// The grid scope the calendar surface renders (spec §9). Day/Week show an hour
/// axis; Month shows a density/agenda grid.
public enum CalendarScope: String, CaseIterable, Sendable, Identifiable {
    case day
    case week
    case month

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    /// Number of days the scope spans starting from its anchor's period start.
    public var dayCount: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 42  // 6 weeks grid
        }
    }
}
