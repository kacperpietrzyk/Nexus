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

    /// Lift a too-dark color to `minBrightness` luma without touching its hue
    /// (saturation 1.0 path of `desaturated` math, exposed separately so the
    /// liquid tint keeps the calendar's real hue).
    func brightnessFloored(_ minBrightness: Double = 0.5) -> CalendarRGB {
        let luma = 0.299 * red + 0.587 * green + 0.114 * blue
        guard luma < minBrightness, luma > 0 else { return clamped() }
        let lift = minBrightness / luma
        return CalendarRGB(red: red * lift, green: green * lift, blue: blue * lift).clamped()
    }

    /// Darkened block-fill triple following the `DS.ColorToken.event*Fill`
    /// convention (fill RGB ≈ accent × 0.3 — e.g. #2997FF → #0C3054); the
    /// caller applies the token alpha.
    func liquidFillBase() -> CalendarRGB {
        let accent = brightnessFloored()
        return CalendarRGB(red: accent.red * 0.3, green: accent.green * 0.3, blue: accent.blue * 0.3)
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

/// Liquid glass tint derived from an EventKit calendar color, following the
/// `DS.ColorToken.event*` convention (dark fill at A6 alpha, accent stroke at
/// 66 alpha, opaque accent for pills/capsules). Real presentation metadata —
/// the same color Apple Calendar shows for the event's calendar — so the week
/// grid can distinguish calendars without inventing categories.
struct LiquidCalendarTint {
    let fill: Color
    let stroke: Color
    let accent: Color

    /// nil for absent/malformed hex so callers fall back to the kind tokens.
    init?(calendarHex string: String?) {
        guard let string, let rgb = CalendarRGB(calendarHex: string) else { return nil }
        let accentRGB = rgb.brightnessFloored()
        // Alphas mirror DS.ColorToken.event*Fill (0xA6) / *Stroke (0x66).
        self.fill = rgb.liquidFillBase().color.opacity(0xA6 / 255.0)
        self.stroke = accentRGB.color.opacity(0x66 / 255.0)
        self.accent = accentRGB.color
    }
}
