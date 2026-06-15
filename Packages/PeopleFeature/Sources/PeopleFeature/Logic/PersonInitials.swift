import Foundation

/// Initials shown in the Liquid avatar pill: first letters of the first two
/// whitespace-separated name parts, uppercased; "?" for empty names. Pure so
/// the avatar's only logic stays unit-testable (mirrors the private
/// `NexusAvatar.initials` of the pre-Liquid primitive).
public enum PersonInitials {
    public static func initials(from name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
        let value = parts.compactMap { $0.first?.uppercased() }.joined()
        return value.isEmpty ? "?" : value
    }
}
