import SwiftUI

/// Pure achromatic foundation — genuinely zero hue (R == G == B).
/// State is expressed via shape, weight, contrast, motion, and glyph — never
/// color. Token ladder: Background → Glass → Line → Text. No scaffold enums.
///
/// The MP-6.3 teardown removed accent/semantic *hues* but the surviving
/// base grays were still cool-biased (B > R,G — a v4 "coss-azure" OKLCH
/// relic). On large translucent panels over the wallpaper glow that bias
/// read as a visible blue (audit #14, user-reported "wpada w niebieski").
/// Every `Color(hex:)` below is now a true neutral gray whose value is the
/// Rec.601 luma (0.299R + 0.587G + 0.114B) of the former cool token, so
/// perceived lightness is preserved app-wide while the chroma is zero.
public enum NexusColor {

    public enum Background {
        public static let base = Color(hex: 0x0A0A0A)  // was 0x090A0C
        public static let panel = Color(hex: 0x0E0E0E)  // was 0x0D0E11
        public static let raised = Color(hex: 0x151515)  // was 0x141519
        public static let control = Color(hex: 0x1A1A1A)  // was 0x191A1F
        public static let controlHover = Color(hex: 0x1F1F1F)  // was 0x1E1F25
    }

    public enum Glass {
        public static let surface1 = Color.white.opacity(0.05)
        public static let surface2 = Color.white.opacity(0.06)
        public static let surface3 = Color.white.opacity(0.10)
    }

    public enum Line {
        public static let hairline = Color.white.opacity(0.07)
        public static let regular = Color.white.opacity(0.10)
        public static let strong = Color.white.opacity(0.16)
    }

    public enum Text {
        public static let primary = Color(hex: 0xF2F2F2)  // was 0xF2F2F4
        public static let secondary = Color(hex: 0xC8C8C8)  // was 0xC7C8CE
        public static let tertiary = Color(hex: 0x8E8E8E)  // was 0x8C8D96
        public static let muted = Color(hex: 0x646464)  // was 0x62636D
        public static let disabled = Color(hex: 0x464646)  // was 0x44454E
    }
}
