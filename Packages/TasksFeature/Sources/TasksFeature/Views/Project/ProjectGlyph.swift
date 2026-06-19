import Foundation

/// Single internal source mapping a project's stored token name → SF Symbol glyph + human shape
/// label. The token-name vocabulary (azure/gold/emerald/rose/violet/slate) is a frozen legacy hue
/// label retained to avoid schema migration (§5), reinterpreted as a glyph key since MP-2.1
/// slice 3c — no color is rendered.
struct ProjectGlyphEntry {
    let glyph: String
    let label: String
}

let projectGlyphTable: [String: ProjectGlyphEntry] = [
    "azure": ProjectGlyphEntry(glyph: "circle.fill", label: "Circle"),
    "gold": ProjectGlyphEntry(glyph: "square.fill", label: "Square"),
    "emerald": ProjectGlyphEntry(glyph: "triangle.fill", label: "Triangle"),
    "rose": ProjectGlyphEntry(glyph: "diamond.fill", label: "Diamond"),
    "violet": ProjectGlyphEntry(glyph: "hexagon.fill", label: "Hexagon"),
    "slate": ProjectGlyphEntry(glyph: "seal.fill", label: "Seal"),
]

/// Legacy token → SF Symbol lookup. Returns the fixed shape mapped to
/// `tokenName`, falling back to `circle.fill`. Use this only for picker
/// swatches that must reflect the token choice itself (e.g. the color-token
/// selector in `ProjectEditorSheet`). For identity display (sidebar rows,
/// Today card, grid tiles) use `nexusProjectGlyph(token:id:)` instead,
/// which derives a distinct shape for default-token ("azure") projects.
public func nexusProjectGlyph(named tokenName: String) -> String {
    projectGlyphTable[tokenName]?.glyph ?? "circle.fill"
}

func projectShapeLabel(named tokenName: String) -> String {
    projectGlyphTable[tokenName]?.label ?? "Circle"
}

/// The token `ProjectRepository.create` assigns by default. Treated as "unset"
/// for display: migrated projects all carry "azure", so deriving a shape from
/// the id keeps the Grid/Roadmap/sidebar from showing identical circles.
public let projectDefaultColorToken = "azure"

/// Deterministic shape order — index space for id-derived identity.
private let projectGlyphShapeOrder = [
    "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill",
]

/// Display glyph for a project. An explicitly-chosen non-default token keeps its
/// mapped shape; the default ("azure") or any unknown token derives a stable
/// shape from the project id. No color is rendered (§MP-2.1).
public func nexusProjectGlyph(token: String, id: UUID) -> String {
    if token != projectDefaultColorToken, let entry = projectGlyphTable[token] {
        return entry.glyph
    }
    // Sum the 16 uuid bytes for a run-stable index (Hasher is per-run seeded).
    let sum = withUnsafeBytes(of: id.uuid) { raw in raw.reduce(0) { $0 + Int($1) } }
    return projectGlyphShapeOrder[sum % projectGlyphShapeOrder.count]
}
