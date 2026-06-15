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

/// Public (not internal like the rest of this file): exported for app-shell
/// composition — the Mac `LiquidSidebar` renders the same identity glyph the
/// Projects screen shows for each project, without duplicating this table.
public func nexusProjectGlyph(named tokenName: String) -> String {
    projectGlyphTable[tokenName]?.glyph ?? "circle.fill"
}

func projectShapeLabel(named tokenName: String) -> String {
    projectGlyphTable[tokenName]?.label ?? "Circle"
}
