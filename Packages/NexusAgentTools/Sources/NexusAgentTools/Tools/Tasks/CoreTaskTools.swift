import Foundation

/// Convenience builder for all core tools that do not depend on TasksFeature.
/// Includes `tasks.*`, `comments.*`, `activity.*`, `note.*`, the Projects-tier `projects.*`,
/// `labels.*`, `agents.*`, `blocks.*` tools (spec §10), the People/Contacts
/// `people.*` tools (spec §7), `cycles.*`, `search.*`, the `saved_filters.*` tools,
/// the `calendar.preferences.*` tools, and the `stats.*` tools.
public enum CoreTaskTools {
    public static func all() -> [any AgentTool] {
        tasksAndNotes + projectsTier + peopleCyclesSearch + savedFilters + calendarPreferences + stats
    }

    /// `stats.*` tools — `stats.goals.*` wrap `UserDefaultsGoalsPreferencesStore`
    /// (the `calendarPreferences` pattern); `stats.productivity` reads completion
    /// counts through the task repository.
    private static var stats: [any AgentTool] {
        [
            StatsGoalsGetTool(),
            StatsGoalsUpdateTool(),
            StatsProductivityTool(),
        ]
    }

    /// `calendar.preferences.*` tools — thin wrappers over
    /// `UserDefaultsCalendarPreferencesStore`. No EventKit dependency (unlike the
    /// `CalendarAgentTools` schedule/event tools), so they live with the core set.
    private static var calendarPreferences: [any AgentTool] {
        [
            CalendarPreferencesGetTool(),
            CalendarPreferencesUpdateTool(),
        ]
    }

    /// `saved_filters.*` tools — thin wrappers over `SavedFilterRepository`.
    private static var savedFilters: [any AgentTool] {
        [
            SavedFiltersListTool(),
            SavedFiltersCreateTool(),
            SavedFiltersUpdateTool(),
            SavedFiltersDeleteTool(),
            SavedFiltersApplyTool(),
        ]
    }

    /// `tasks.*`, `comments.*`, `activity.*`, and `note.*` tools.
    private static var tasksAndNotes: [any AgentTool] {
        [
            TasksGetTool(),
            TasksListTool(),
            TasksSearchTool(),
            TasksCreateTool(),
            TasksCreateIdempotentTool(),
            TasksUpdateTool(),
            TasksCompleteTool(),
            TasksReopenTool(),
            TasksSnoozeTool(),
            TasksSetRemindersTool(),
            TasksDeleteTool(),
            TasksInstantiateTemplateTool(),
            CommentsListTool(),
            CommentsAddTool(),
            CommentsEditTool(),
            CommentsDeleteTool(),
            ActivityGetTool(),
            NotesCreateTool(),
            NotesUpdateTool(),
            NotesGetTool(),
            NotesListTool(),
            NotesSearchTool(),
            NotesLinkTool(),
            NotesDeleteTool(),
        ]
    }

    /// Projects tier (spec §10): `projects.*`, `projects.sections.*`, `labels.*`,
    /// `agents.*`, `blocks.*`, and the task workflow/agent-assignment tools.
    private static var projectsTier: [any AgentTool] {
        [
            ProjectsCreateTool(),
            SectionsCreateTool(),
            ProjectsGetTool(),
            ProjectsSetStatusTool(),
            ProjectsListTool(),
            ProjectsUpdateTool(),
            ProjectsArchiveTool(),
            ProjectsUnarchiveTool(),
            ProjectsDeleteTool(),
            SectionsListTool(),
            SectionsUpdateTool(),
            SectionsDeleteTool(),
            SectionsReorderTool(),
            TasksSetWorkflowStateTool(),
            TasksAssignAgentTool(),
            AgentsQueueTool(),
            LabelsListAllTool(),
            LabelsListForTool(),
            LabelsAssignTool(),
            LabelsRemoveTool(),
            LabelsCreateTool(),
            LabelsUpdateTool(),
            LabelsDeleteTool(),
            BlocksListTool(),
            BlocksAddTool(),
            BlocksRemoveTool(),
        ]
    }

    /// People/Contacts module (spec §7), Cycles (Tranche 2 Plan C), and the
    /// unified `search.global` tool (Tranche 2).
    private static var peopleCyclesSearch: [any AgentTool] {
        [
            PeopleCreateTool(),
            PeopleCreateIdempotentTool(),
            PeopleUpdateTool(),
            PeopleGetTool(),
            PeopleListTool(),
            PeopleSearchTool(),
            PeopleAggregateTool(),
            PeopleLinkTool(),
            PeopleMergeTool(),
            CyclesListTool(),
            CyclesAssignTool(),
            CyclesCreateTool(),
            CyclesUpdateTool(),
            CyclesSetStatusTool(),
            CyclesDeleteTool(),
            SearchGlobalTool(),
        ]
    }
}
