import Foundation

/// The canonical seed set of system labels (Projects tier, spec §7). Seeded with
/// `isSystem = true` (non-deletable from the UI) by `LabelRepository.seedSystemLabels`
/// (idempotently) and, later, by the schema migration step.
///
/// A single source of truth so the repo seed and any migration agree on names,
/// groups, and glyphs. Names are matched case-insensitively against existing rows
/// to keep the seed idempotent (CloudKit forbids `@Attribute(.unique)`).
public enum SystemLabel: String, CaseIterable, Sendable {
    // domain (single-select)
    case feature
    case bug
    case infra
    case security

    // gate (single-select)
    case needsDecision
    case decided

    /// Deterministic, stable identity for the seeded `Label` row. Because `Label`
    /// is a synced (CloudKit) partition and CloudKit forbids `@Attribute(.unique)`,
    /// two devices first-launching before the seed has synced would each mint a
    /// fresh `UUID()` and produce duplicate rows by name. Seeding with a fixed id
    /// per system label makes record identity converge — CloudKit merges the two
    /// inserts into one record instead of duplicating. NEVER change these values.
    public var id: UUID {
        switch self {
        case .feature: return UUID(uuidString: "5A1E0000-0000-4000-A000-000000000001")!
        case .bug: return UUID(uuidString: "5A1E0000-0000-4000-A000-000000000002")!
        case .infra: return UUID(uuidString: "5A1E0000-0000-4000-A000-000000000003")!
        case .security: return UUID(uuidString: "5A1E0000-0000-4000-A000-000000000004")!
        case .needsDecision: return UUID(uuidString: "5A1E0000-0000-4000-A000-000000000005")!
        case .decided: return UUID(uuidString: "5A1E0000-0000-4000-A000-000000000006")!
        }
    }

    /// The label group this system label belongs to.
    public var group: LabelGroup {
        switch self {
        case .feature, .bug, .infra, .security:
            return .domain
        case .needsDecision, .decided:
            return .gate
        }
    }

    /// Human-facing name persisted on `Label.name`.
    public var name: String { rawValue }

    /// Achromatic glyph key persisted on `Label.glyphKey` (LabKit — never a color).
    public var glyphKey: String {
        switch self {
        case .feature: return "sparkles"
        case .bug: return "ant"
        case .infra: return "server.rack"
        case .security: return "lock.shield"
        case .needsDecision: return "questionmark.circle"
        case .decided: return "checkmark.seal"
        }
    }
}
