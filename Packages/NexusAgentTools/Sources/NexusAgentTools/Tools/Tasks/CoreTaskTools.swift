import Foundation

/// Convenience builder for all core tools that do not depend on TasksFeature.
/// Includes `tasks.*`, `comments.*`, `activity.*`, `note.*`, the Projects-tier `projects.*`,
/// `labels.*`, `agents.*`, `blocks.*` tools (spec §10), and the People/Contacts
/// `people.*` tools (spec §7).
public enum CoreTaskTools {
    public static func all() -> [any AgentTool] {
        tasksAndNotes + projectsTier + peopleCyclesSearch
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
