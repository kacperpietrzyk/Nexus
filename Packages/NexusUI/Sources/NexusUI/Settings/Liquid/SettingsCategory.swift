import SwiftUI

/// The 7 consolidated left-rail categories for the macOS Settings two-pane.
public enum SettingsCategory: String, CaseIterable, Identifiable, Sendable {
    case general, sync, tasks, aiModels, meetings, advanced, about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .sync: return "Sync"
        case .tasks: return "Tasks"
        case .aiModels: return "AI & Models"
        case .meetings: return "Meetings"
        case .advanced: return "Advanced"
        case .about: return "About"
        }
    }

    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .sync: return "icloud"
        case .tasks: return "checklist"
        case .aiModels: return "sparkles"
        case .meetings: return "person.2.wave.2"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }
}
