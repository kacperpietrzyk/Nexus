import Foundation

/// TasksFeature — Tasks module entry point. Phase 1c ships only the NL parser
/// (`NLParser`, `HandcodedParser`, `FoundationModelParser`, `CompositeNLParser`).
/// `bootstrap()` registry calls (Inbox sources, ⌘K commands) land in sub-plan 1g.
public enum TasksFeature {
    public static let version = "0.1.0"
}
