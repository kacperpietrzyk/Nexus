import Foundation
import NexusCore

/// Wire format for `Label` exposed via MCP (Projects tier, spec §10). snake_case
/// keys per MCP convention. `group` is the `LabelGroup` raw value
/// (domain/gate/free); `glyph` is the achromatic glyph key (LabKit — never a color).
public struct LabelDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let group: String
    public let glyph: String
    public let isSystem: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, group, glyph
        case isSystem = "is_system"
    }

    public init(id: String, name: String, group: String, glyph: String, isSystem: Bool) {
        self.id = id
        self.name = name
        self.group = group
        self.glyph = glyph
        self.isSystem = isSystem
    }

    public init(from label: Label) {
        self.init(
            id: label.id.uuidString,
            name: label.name,
            group: label.group.rawValue,
            glyph: label.glyphKey,
            isSystem: label.isSystem
        )
    }
}
