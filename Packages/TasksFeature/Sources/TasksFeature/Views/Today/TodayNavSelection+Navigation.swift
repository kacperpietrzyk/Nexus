// Navigation vocabulary for `TodayNavSelection`: stable string `token` (for
// persistence / `NavLocation`), its inverse `from(token:)`, and the
// human-readable `title` used by shell breadcrumbs.
//
// Lives on the enum in its own module so the lower layers (which map to/from
// tokens) never need to import TasksFeature. This is the single source of truth
// for destination labels — `ContentView.shellTitle` delegates to `title`.

extension TodayNavSelection {
    /// Stable string token for persistence / `NavLocation.destinationToken`.
    /// Never localize — this is an identifier, not display text.
    public var token: String {
        switch self {
        case .today: return "today"
        case .inbox: return "inbox"
        case .meetings: return "meetings"
        case .tasks: return "tasks"
        case .projects: return "projects"
        case .notes: return "notes"
        case .calendar: return "calendar"
        case .people: return "people"
        case .agent: return "agent"
        case .stats: return "stats"
        case .settings: return "settings"
        }
    }

    /// Inverse of `token`. Returns `nil` for an unrecognized token.
    public static func from(token: String) -> TodayNavSelection? {
        switch token {
        case "today": return .today
        case "inbox": return .inbox
        case "meetings": return .meetings
        case "tasks": return .tasks
        case "projects": return .projects
        case "notes": return .notes
        case "calendar": return .calendar
        case "people": return .people
        case "agent": return .agent
        case "stats": return .stats
        case "settings": return .settings
        default: return nil
        }
    }

    /// Human-readable breadcrumb / shell title. Single source of truth —
    /// `ContentView.shellTitle` delegates here. `.agent` reads "Nexus" by design.
    public var title: String {
        switch self {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .meetings: return "Meetings"
        case .tasks: return "Tasks"
        case .projects: return "Projects"
        case .notes: return "Notes"
        case .calendar: return "Calendar"
        case .people: return "People"
        case .agent: return "Nexus"
        case .stats: return "Stats"
        case .settings: return "Settings"
        }
    }
}
