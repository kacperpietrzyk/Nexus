import Foundation

/// Configuration value for the `assistant.chat` skill.
///
/// Captures persona, curated read-only tool subset, context recipe, and
/// the "propose, don't mutate" prompt contract. Executed through
/// `AgentRuntime` (not `SkillRunner`) so the dispatch-and-continue loop,
/// message persistence, and tool dispatch remain intact.
public struct AssistantChatConfig: Sendable {
    public let systemPrompt: String
    /// Tool names the model is allowed to call during a chat turn.
    /// Write tools (`tasks.create`, `tasks.update`) are excluded; any change
    /// the model suggests must appear in a structured `nexus-proposal` block.
    public let toolNames: [String]
    /// Maximum dispatch-and-continue iterations per turn.
    public let maxIterations: Int
    /// Whether the model is permitted to make tool calls mid-turn.
    /// `false` on iOS (extraction-only path; context is pre-stuffed).
    public let allowsToolCalling: Bool
    /// Context recipe used when assembling a stuffed context for iOS turns.
    public let contextRecipe: ContextRecipe

    public init(
        systemPrompt: String,
        toolNames: [String],
        maxIterations: Int,
        allowsToolCalling: Bool,
        contextRecipe: ContextRecipe
    ) {
        self.systemPrompt = systemPrompt
        self.toolNames = toolNames
        self.maxIterations = maxIterations
        self.allowsToolCalling = allowsToolCalling
        self.contextRecipe = contextRecipe
    }
}

// MARK: - Platform presets

extension AssistantChatConfig {
    /// Read-only tool subset available to both presets.
    /// All names confirmed present in NexusAgentTools. Write tools
    /// (`tasks.create`, `tasks.update`) are intentionally absent —
    /// they are proposed via a structured block, never tool-called.
    private static let readOnlyTools: [String] = [
        "search.global",
        "tasks.list",
        "tasks.get",
        "tasks.search",
        "projects.get",
        "projects.list",
        "people.get",
        "people.search",
        "note.search",
        "activity.get",
        "stats.productivity",
        "stats.goals.get",
    ]

    /// Mac preset: read-only tool-calling, up to 3 iterations.
    public static let mac = AssistantChatConfig(
        systemPrompt: sharedSystemPrompt,
        toolNames: readOnlyTools,
        maxIterations: 3,
        allowsToolCalling: true,
        contextRecipe: ContextRecipe(
            includeEntity: false,
            linkGraphDepth: 0,
            repoSlices: [.tasksDueWithin(days: 7)],
            ragQuery: nil,
            tokenBudget: 2_000
        )
    )

    /// iOS preset: extraction-only (no tool calls; context pre-stuffed via ContextAssembler).
    public static let iOS = AssistantChatConfig(
        systemPrompt: sharedSystemPrompt,
        toolNames: [],
        maxIterations: 2,
        allowsToolCalling: false,
        contextRecipe: ContextRecipe(
            includeEntity: true,
            linkGraphDepth: 1,
            repoSlices: [.tasksDueWithin(days: 7), .overdueTasks],
            ragQuery: RagQuerySpec(query: "", limit: 5),
            tokenBudget: 3_000
        )
    )

    // MARK: - Shared system prompt

    private static let sharedSystemPrompt = """
        You are Nexus Assistant, the personal AI inside Nexus — a productivity app \
        that stores the user's tasks, projects, notes, meetings, and contacts locally.

        ## Role
        Answer questions about the user's data. Read tools are available so you can \
        look up tasks, projects, people, notes, activity, and stats. \
        Use them to ground every answer in the user's actual data.

        ## House rules
        - Be concise and direct. Prioritise facts from tool results over assumptions.
        - Do not fabricate task titles, project names, or dates that you have not read.
        - Reply in the user's language; default to English if uncertain.
        - You may suggest next steps or surface patterns, but keep the tone grounded.

        ## Propose, don't mutate
        You MUST NOT call `tasks.create`, `tasks.update`, or any other write tool. \
        Those tools are not in your allowed set.

        If the user asks you to create or change something, describe your intended \
        action and append a SINGLE structured block using EXACTLY this format:

        ```nexus-proposal
        {
          "rationale": "<one-sentence explanation of what you are proposing and why>",
          "mutations": [
            {
              "tool": "tasks.create",
              "args": { "title": "<task title>", "notes": "<optional notes>" }
            }
          ]
        }
        ```

        Rules for the proposal block:
        - Only `tasks.create` and `tasks.update` are valid values for `"tool"`.
        - Emit at most ONE block per turn; omit it entirely for read-only answers.
        - The JSON inside the fence must be valid; malformed JSON is silently dropped.
        - Do NOT call any write tools — proposals are the only mutation path.

        The app will parse the block, display a confirm card, and apply it only if \
        the user explicitly accepts. Until then nothing is written.
        """
}
