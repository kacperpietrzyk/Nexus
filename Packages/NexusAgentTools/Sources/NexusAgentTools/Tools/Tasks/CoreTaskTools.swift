import Foundation

/// Convenience builder for all core tools that do not depend on TasksFeature.
/// Includes `tasks.*`, `comments.*`, `activity.*`, `note.*`, the Projects-tier `projects.*`,
/// `labels.*`, `agents.*`, `blocks.*` tools (spec §10), the People/Contacts
/// `people.*` tools (spec §7), `cycles.*`, `search.*`, the `saved_filters.*` tools,
/// the `calendar.preferences.*` tools, the `stats.*` tools, and `organizations.*` tools.
public enum CoreTaskTools {
    public static func all() -> [any AgentTool] {
        tasksAndNotes + projectsTier + peopleCyclesSearch + savedFilters + calendarPreferences + stats + export
            + organizations + linkEnumeration + trash + attachments
    }

    // TODO: surface a configurable ingest root in Settings (v1 defaults to home dir).
    // TODO: add `attachments.add_to_task` once a task attachment surface exists.
    //
    /// `attachments.*` tools — path/URL handoff for local image files (spec §7).
    /// `add_to_note` ingests a host-filesystem path behind `AttachmentIngestPolicy`
    /// and appends an image block; `list`/`remove` manage the asset rows.
    private static var attachments: [any AgentTool] {
        [
            AttachmentsAddToNoteTool(),
            AttachmentsListTool(),
            AttachmentsRemoveTool(),
        ]
    }

    /// `items.*` trash tools — kind-polymorphic `items.list_deleted` (fetch soft-deleted
    /// rows of a kind) and `items.restore` (undelete via the generic `LinkableRepository`).
    private static var trash: [any AgentTool] {
        [
            ItemsListDeletedTool(),
            ItemsRestoreTool(),
        ]
    }

    /// `links.*` tools — read-only enumeration of the polymorphic `Link` graph
    /// (backlinks / outgoing edges / whole-graph dump). Thin wrappers over
    /// `LinkRepository`.
    private static var linkEnumeration: [any AgentTool] {
        [
            LinksBacklinksTool(),
            LinksOutgoingTool(),
            LinksListTool(),
        ]
    }

    /// `export.*` tools — anti-lock-in Markdown export. `export.item` renders one
    /// entity to a string; `export.bundle` writes the whole-vault folder.
    private static var export: [any AgentTool] {
        [
            ExportItemTool(),
            ExportBundleTool(),
        ]
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
            TasksReorderTool(),
            TasksDeleteTool(),
            TasksMergeTool(),
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
            ProjectsSetStageTool(),
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
            ProjectsSetKeyDateTool(),
            ProjectsListKeyDatesTool(),
            ProjectsDeleteKeyDateTool(),
        ]
    }

    /// `organizations.*` tools — client/account Organizations (universal-types extension).
    private static var organizations: [any AgentTool] {
        [
            OrganizationsCreateTool(),
            OrganizationsListTool(),
            OrganizationsGetTool(),
            OrganizationsUpdateTool(),
            OrganizationsLinkPersonTool(),
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
            PeopleSuggestDuplicatesTool(),
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
