import Foundation

/// Stable @AppStorage keys + enum types used across Settings sections. Raw values land in
/// UserDefaults — NEVER rename without a migration shim.
public enum NexusPreferences {
    private static let legacyAgentPreloadSpeechKey = "nexus.agent.preloadSpeech"
    // MP-3.2 promoted Agent from a toggled HSplitView pane to a full shell
    // destination, retiring this flag. Purged from UserDefaults on Mac launch.
    private static let legacyAgentSidebarOpenKey = "nexus.agent.sidebarOpen"

    public enum Keys {
        public static let theme = "nexus.general.theme"
        public static let mcpEnabled = "nexus.mcp.enabled"
        /// Master visibility toggle for power-user Settings surfaces. Default false.
        public static let advancedEnabled = "nexus.advanced.uiVisibility"
        /// Set after the user finishes or skips the first-launch welcome flow.
        public static let welcomeShown = "nexus.welcome.shown"
        /// Chat model ID chosen during the MLX welcome screen. Nil when unset.
        public static let selectedWelcomeChatModelID = "nexus.welcome.mlx.selectedChatModelID"
        /// Embedder model ID chosen during the MLX welcome screen. Nil when unset.
        public static let selectedWelcomeEmbedderID = "nexus.welcome.mlx.selectedEmbedderID"
        /// True when the user explicitly skipped on-device model setup during welcome.
        public static let skipWelcomeMLX = "nexus.welcome.mlx.skipMLX"
        public static let calendarEventsInTodayEnabled = "nexus.calendar.eventsInTodayEnabled"
        /// Master enablement switch for Agent surfaces and background work. Default true at the app storage call site.
        public static let agentEnabled = "nexus.agent.enabled"
        /// Agent memory candidate auto-save. Default true at the app storage call site.
        public static let agentMemoryAutoSaveEnabled = "nexus.agent.memory.autoSaveEnabled"
        /// Pauses scheduled Agent runs while keeping manual chat available. Default false.
        public static let agentVacationMode = "nexus.agent.vacationMode"
        /// Preloads the local WhisperKit transcription model at app launch. Default false.
        public static let agentVoicePreloadWhisperKit = "nexus.agent.voice.preloadWhisperKit"
        /// Keeps speech components warm for lower-latency voice capture. Default false.
        public static let agentPreloadSpeech = agentVoicePreloadWhisperKit
        /// Auto-unloads idle MLX models to reclaim RAM (iOS: 2 min, Mac: 10 min). Default true.
        public static let mlxAutoUnloadEnabled = "nexus.mlx.autoUnload.enabled"
        /// Preloads the assigned MLX chat model at app launch for zero first-message latency. Default false.
        public static let mlxPreloadChat = "nexus.mlx.preload.chat"
        /// User-facing display name greeted in Today's dashboard. Empty string means fall back to
        /// `NSFullUserName()` on Mac / `UIDevice.current.name` on iOS / "You" otherwise.
        public static let workspaceDisplayName = "nexus.workspace.displayName"
        /// iPad-only: suppresses Auto-Lock (`isIdleTimerDisabled`) while Nexus is
        /// foreground-active, for desk-companion always-on use. Default false.
        public static let keepScreenAwakeEnabled = "nexus.display.keepScreenAwake"
    }

    public static func migrateLegacyAgentPreloadSpeechKey(defaults: UserDefaults = .standard) {
        let oldKey = legacyAgentPreloadSpeechKey
        let newKey = Keys.agentVoicePreloadWhisperKit
        guard defaults.object(forKey: newKey) == nil,
            defaults.object(forKey: oldKey) != nil
        else {
            return
        }

        defaults.set(defaults.bool(forKey: oldKey), forKey: newKey)
    }

    /// Removes the retired `nexus.agent.sidebarOpen` key from UserDefaults.
    /// MP-3.2 promoted Agent to a full shell destination (no toggled pane),
    /// so this flag has no meaning. Call once at Mac app launch.
    public static func purgeLegacyAgentSidebarOpenKey(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyAgentSidebarOpenKey)
    }
}

public enum NexusTheme: String, CaseIterable, Sendable, Hashable {
    case amberDark
}
