import SwiftUI

/// Linear "Midnight Command Center" layered-dark palette.
///
/// Five surface levels (Background) form a depth ladder from Pitch Black (#08090A)
/// up through Charcoal Grey (#23252A). Text and Line tokens carry deliberate cool
/// bias (Light Steel, Storm Cloud) matching the Linear specification.
///
/// `Accent.lime` is the **only** saturated accent and is reserved exclusively
/// for primary-action surfaces — do NOT apply it to base tokens or secondary
/// UI chrome. Liquid re-skin: the token now resolves to the Liquid violet
/// (`DS.ColorToken.accentPrimary`, #6D5DFB); the Linear Neon Lime value is
/// superseded. The token NAME is kept so every existing call site re-points
/// in one diff (cross-platform — iOS/Watch join the liquid family too).
///
/// Token ladder: Background → Glass → Line → Text → Accent → Status.
/// `Glass` is retained for incremental de-glass sweeps; prefer flat `Background`
/// surfaces + `NexusShadow` for elevation in new code.
public enum NexusColor {

    public enum Background {
        public static let base = Color(hex: 0x08090A)  // Pitch Black
        public static let panel = Color(hex: 0x0F1011)  // Graphite
        public static let raised = Color(hex: 0x161718)  // Deep Slate
        public static let control = Color(hex: 0x1C1D1F)  // between Deep Slate and Charcoal Grey
        public static let controlHover = Color(hex: 0x23252A)  // Charcoal Grey
    }

    public enum Glass {
        public static let surface1 = Color.white.opacity(0.05)
        public static let surface2 = Color.white.opacity(0.06)
        public static let surface3 = Color.white.opacity(0.10)
    }

    public enum Line {
        public static let hairline = Color(hex: 0x23252A)  // Charcoal Grey (subtle border)
        public static let regular = Color(hex: 0x2C2E33)  // Muted Ash region
        public static let strong = Color(hex: 0x383B3F)  // Gunmetal (input border)
    }

    public enum Text {
        public static let primary = Color(hex: 0xF7F8F8)  // Porcelain
        public static let secondary = Color(hex: 0xD0D6E0)  // Light Steel
        public static let tertiary = Color(hex: 0x8A8F98)  // Storm Cloud
        public static let muted = Color(hex: 0x62666D)  // Fog Grey
        public static let disabled = Color(hex: 0x4A4D52)  // muted ash region
    }

    /// Primary accent — primary action surfaces only.
    /// Never apply `lime` to base backgrounds, borders, or secondary chrome.
    ///
    /// Liquid re-skin: re-valued from the Linear Neon Lime (#E4F222 / pitch-black
    /// ink) to the Liquid violet (#6D5DFB == `DS.ColorToken.accentPrimary`) with
    /// white ink. Contrast audit: every `limeInk` call site draws ink ON a `lime`
    /// fill; white on #6D5DFB is ≈4.55:1 (WCAG AA), and all sites are small
    /// semibold labels/icons.
    public enum Accent {
        /// Liquid violet (#6D5DFB) — fill for primary action elements.
        /// (Historic name; the Linear lime value is superseded.)
        public static let lime = Color(hex: 0x6D5DFB)
        /// White — text/icon drawn on top of an accent surface.
        /// (Historic name; was pitch black on the Linear lime.)
        public static let limeInk = Color(hex: 0xFFFFFF)
    }

    /// Semantic status colors for success, informational, and danger states.
    public enum Status {
        /// Emerald (#27A644) — success and completion states.
        public static let success = Color(hex: 0x27A644)
        /// Cyan Spark (#02B8CC) — informational highlights.
        public static let info = Color(hex: 0x02B8CC)
        /// Warning Red (#EB5757) — error and danger states.
        public static let danger = Color(hex: 0xEB5757)
    }
}
