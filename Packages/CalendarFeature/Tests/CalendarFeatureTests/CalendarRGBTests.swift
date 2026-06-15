import Testing

@testable import CalendarFeature

@Suite("CalendarRGB desaturation")
struct CalendarRGBTests {

    @Test("Parses #RRGGBB and bare RRGGBB into 0...1 components")
    func parsesHex() throws {
        let withHash = try #require(CalendarRGB(calendarHex: "#FF8000"))
        #expect(abs(withHash.red - 1.0) < 0.001)
        #expect(abs(withHash.green - 128.0 / 255.0) < 0.001)
        #expect(withHash.blue == 0)

        let bare = try #require(CalendarRGB(calendarHex: "FF8000"))
        #expect(bare == withHash)
    }

    @Test("Rejects malformed hex")
    func rejectsMalformed() {
        #expect(CalendarRGB(calendarHex: "12345") == nil)
        #expect(CalendarRGB(calendarHex: "GGGGGG") == nil)
        #expect(CalendarRGB(calendarHex: "") == nil)
    }

    @Test("Desaturation pulls channels toward luminance (cuts saturation)")
    func reducesSaturation() throws {
        // Pure saturated red.
        let red = try #require(CalendarRGB(calendarHex: "FF0000"))
        let out = red.desaturated(saturation: 0.55, minBrightness: 0.0)
        // The channel spread must shrink: green/blue rise toward the luma grey
        // point, red falls toward it. Original spread is 1.0; output is smaller.
        let inSpread = red.red - red.blue
        let outSpread = out.red - out.blue
        #expect(outSpread < inSpread)
        #expect(out.green > red.green)  // pulled up toward luma
        #expect(out.red < red.red)  // pulled down toward luma
    }

    @Test("A grey input stays grey (no hue introduced)")
    func greyStaysGrey() throws {
        let grey = try #require(CalendarRGB(calendarHex: "808080"))
        let out = grey.desaturated(minBrightness: 0.0)
        #expect(abs(out.red - out.green) < 0.0001)
        #expect(abs(out.green - out.blue) < 0.0001)
    }

    @Test("A dark calendar color is lifted well clear of the background")
    func darkColorLifted() throws {
        // Very dark blue — would vanish on the dark palette without the lift.
        let darkBlue = try #require(CalendarRGB(calendarHex: "000040"))
        let inLuma = 0.299 * darkBlue.red + 0.587 * darkBlue.green + 0.114 * darkBlue.blue
        let floored = darkBlue.desaturated(saturation: 0.55, minBrightness: 0.5)
        let outLuma = 0.299 * floored.red + 0.587 * floored.green + 0.114 * floored.blue
        // The lift multiplies brightness many-fold. The exact floor isn't
        // guaranteed once a channel clamps at 1.0 (near-monochrome inputs), but
        // the result is unambiguously legible vs. the original near-black.
        #expect(outLuma > inLuma * 3)
        #expect(outLuma > 0.25)
        // Hue survives: blue still the dominant channel.
        #expect(floored.blue > floored.red)
        #expect(floored.blue > floored.green)
    }

    @Test("A mid-dark color that doesn't clamp reaches the floor")
    func midDarkReachesFloor() throws {
        // Dark grey-blue, no channel near 1.0 → multiplicative lift hits the floor.
        let midDark = try #require(CalendarRGB(calendarHex: "303040"))
        let floored = midDark.desaturated(saturation: 0.55, minBrightness: 0.5)
        let luma = 0.299 * floored.red + 0.587 * floored.green + 0.114 * floored.blue
        #expect(luma >= 0.49)
    }

    @Test("Output is always clamped into 0...1")
    func clamped() throws {
        let bright = try #require(CalendarRGB(calendarHex: "FFFF00"))
        let out = bright.desaturated(minBrightness: 0.9)
        for channel in [out.red, out.green, out.blue] {
            #expect(channel >= 0)
            #expect(channel <= 1)
        }
    }
}

@Suite("Liquid calendar tint")
struct LiquidCalendarTintTests {

    @Test("Brightness floor lifts dark colors without changing channel ratios")
    func floorKeepsHue() throws {
        let dark = try #require(CalendarRGB(calendarHex: "201008"))
        let lifted = dark.brightnessFloored(0.5)
        let luma = 0.299 * lifted.red + 0.587 * lifted.green + 0.114 * lifted.blue
        #expect(luma >= 0.49)
        // Hue preserved: red:green ratio unchanged by a pure multiplicative lift.
        #expect(abs(lifted.red / lifted.green - dark.red / dark.green) < 0.001)
    }

    @Test("Bright colors pass the floor untouched")
    func floorPassesBright() throws {
        let bright = try #require(CalendarRGB(calendarHex: "2997FF"))
        let out = bright.brightnessFloored(0.5)
        #expect(abs(out.red - bright.red) < 0.001)
        #expect(abs(out.blue - bright.blue) < 0.001)
    }

    @Test("Fill base follows the event-token convention (accent × 0.3)")
    func fillBaseMatchesConvention() throws {
        // The DS pair: stroke #2997FF → fill #0C3054 ≈ accent × 0.3.
        let accent = try #require(CalendarRGB(calendarHex: "2997FF"))
        let fill = accent.liquidFillBase()
        #expect(abs(fill.red - accent.red * 0.3) < 0.001)
        #expect(abs(fill.green - accent.green * 0.3) < 0.001)
        #expect(abs(fill.blue - accent.blue * 0.3) < 0.001)
    }

    @Test("Tint is nil for absent or malformed hex")
    func nilFallback() {
        #expect(LiquidCalendarTint(calendarHex: nil) == nil)
        #expect(LiquidCalendarTint(calendarHex: "nope") == nil)
        #expect(LiquidCalendarTint(calendarHex: "#A2845E") != nil)
    }
}
