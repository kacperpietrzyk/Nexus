import SwiftUI

extension Color {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string into a `Color`, returning nil for
    /// malformed input. Used to tint external events with their EventKit calendar
    /// color (`CalendarEvent.calendarColorHex`).
    init?(calendarHex string: String) {
        var hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}
