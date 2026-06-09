import SwiftUI

/// Pure RGB triple in 0...1, used so calendar-color math is testable without
/// round-tripping through `Color`/`NSColor`/`UIColor` (platform-lossy).
struct CalendarRGB: Equatable {
    var red: Double
    var green: Double
    var blue: Double
}

extension CalendarRGB {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string into linear 0...1 components,
    /// returning nil for malformed input.
    init?(calendarHex string: String) {
        var hex = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.red = Double((value >> 16) & 0xFF) / 255.0
        self.green = Double((value >> 8) & 0xFF) / 255.0
        self.blue = Double(value & 0xFF) / 255.0
    }

    /// Desaturate a raw EventKit calendar color so it sits inside the Midnight
    /// Command Center dark palette: pull each channel toward its luminance
    /// (cutting saturation) while keeping enough hue to distinguish calendars,
    /// then floor brightness so the result reads on a dark surface. Lime stays
    /// the only fully-saturated accent in the app — these tints never compete.
    ///
    /// Pure arithmetic (no `Color`) so the transform is unit-testable directly.
    /// - `saturation`: 0 = grey, 1 = original. Default 0.55 keeps hue legible
    ///   without fighting the palette.
    /// - `minBrightness`: floor applied after desaturation so dark calendar
    ///   colors don't vanish into the background.
    func desaturated(saturation: Double = 0.55, minBrightness: Double = 0.5) -> CalendarRGB {
        // Rec. 601 luma — the grey point we mix toward.
        let luma = 0.299 * red + 0.587 * green + 0.114 * blue
        let mixed = CalendarRGB(
            red: luma + (red - luma) * saturation,
            green: luma + (green - luma) * saturation,
            blue: luma + (blue - luma) * saturation
        )
        // Lift the whole triple if it's too dark to read on the dark palette.
        let mixedLuma = 0.299 * mixed.red + 0.587 * mixed.green + 0.114 * mixed.blue
        guard mixedLuma < minBrightness, mixedLuma > 0 else { return mixed.clamped() }
        let lift = minBrightness / mixedLuma
        return CalendarRGB(
            red: mixed.red * lift,
            green: mixed.green * lift,
            blue: mixed.blue * lift
        )
        .clamped()
    }

    private func clamped() -> CalendarRGB {
        CalendarRGB(
            red: min(1, max(0, red)),
            green: min(1, max(0, green)),
            blue: min(1, max(0, blue))
        )
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1.0)
    }
}

extension Color {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string into a `Color`, returning nil for
    /// malformed input. Used to tint external events with their EventKit calendar
    /// color (`CalendarEvent.calendarColorHex`).
    init?(calendarHex string: String) {
        guard let rgb = CalendarRGB(calendarHex: string) else { return nil }
        self = rgb.color
    }

    /// The event's calendar color, desaturated to sit inside the dark palette.
    /// Returns nil for malformed/absent hex so callers can fall back to a token.
    init?(calendarHexDesaturated string: String) {
        guard let rgb = CalendarRGB(calendarHex: string) else { return nil }
        self = rgb.desaturated().color
    }
}
