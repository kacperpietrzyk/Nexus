/// Tokens for the Liquid Productivity design system.
/// These Swift tokens are the live source of truth; the docs JSON
/// (liquid_productivity_design_system/docs/02_DESIGN_TOKENS.json) is the
/// original reference and may differ — the shipped glass values have since
/// intentionally diverged from it.
import SwiftUI

// MARK: - DS namespace

// swiftlint:disable:next type_name
public enum DS {

    // MARK: ColorToken

    public enum ColorToken {

        // Background
        public static let backgroundApp = Color(hex: 0x05080D)
        public static let backgroundElevated = Color(hex: 0x0A0F16)
        public static let backgroundSunken = Color(hex: 0x020409)
        /// #02050A at CC/255 ≈ 0.80 opacity
        public static let backgroundWallpaperScrim = Color(hex: 0x02050A, alpha: 0xCC / 255.0)

        // Glass tint. These are translucent tints over material; keep them
        // light enough that the scenic layer remains visible through panels.
        public static let glassBase = Color.white.opacity(0.034)
        public static let glassSoft = Color.white.opacity(0.026)
        public static let glassStrong = Color(hex: 0x0B1320, alpha: 0.34)
        public static let glassToolbar = Color.white.opacity(0.030)
        public static let glassSidebar = Color.white.opacity(0.040)
        public static let glassCard = Color.white.opacity(0.024)
        public static let glassCardHover = Color.white.opacity(0.042)
        /// White at 12/255 ≈ 0.07. Intentionally the same value as `strokeHairline`
        /// (#FFFFFF12 in the source JSON) but with a distinct semantic role:
        /// selected surface overlay, not a border.
        public static let glassSelected = Color(hex: 0xFFFFFF, alpha: 0x12 / 255.0)

        // Stroke
        /// white at 12/255 ≈ 0.07
        public static let strokeHairline = Color.white.opacity(0.075)
        /// white at 1C/255 ≈ 0.11
        public static let strokeDefault = Color.white.opacity(0.110)
        /// white at 2B/255 ≈ 0.17
        public static let strokeStrong = Color.white.opacity(0.180)
        /// white at 26/255 ≈ 0.15
        public static let strokeInnerHighlight = Color.white.opacity(0.150)
        /// black at 66/255 ≈ 0.40
        public static let shadowEdge = Color(hex: 0x000000, alpha: 0x66 / 255.0)

        // Text
        public static let textPrimary = Color(hex: 0xF4F7FB)
        public static let textSecondary = Color(hex: 0xAAB4C3)
        public static let textTertiary = Color(hex: 0x737F90)
        public static let textMuted = Color(hex: 0x566173)
        public static let textInverse = Color(hex: 0x05080D)

        // Accent
        public static let accentPrimary = Color(hex: 0x6D5DFB)
        public static let accentPrimaryHover = Color(hex: 0x7C6BFF)
        public static let accentBlue = Color(hex: 0x2997FF)
        public static let accentCyan = Color(hex: 0x35D1FF)
        public static let accentPurple = Color(hex: 0x9B72FF)
        public static let accentGreen = Color(hex: 0x37D67A)
        public static let accentAmber = Color(hex: 0xF7B955)
        public static let accentOrange = Color(hex: 0xFF9F43)
        public static let accentRed = Color(hex: 0xFF5A5F)
        public static let accentPink = Color(hex: 0xFF6AC1)

        // Status
        public static let statusSuccess = Color(hex: 0x37D67A)
        public static let statusWarning = Color(hex: 0xF7B955)
        public static let statusDanger = Color(hex: 0xFF5A5F)
        public static let statusInfo = Color(hex: 0x2997FF)
        public static let statusNeutral = Color(hex: 0x8B95A7)

        // Event fills — #RRGGBB at A6/255 ≈ 0.65 opacity
        public static let eventFocusFill = Color(hex: 0x0C3054, alpha: 0xA6 / 255.0)
        public static let eventFocusStroke = Color(hex: 0x2997FF, alpha: 0x66 / 255.0)
        public static let eventMeetingFill = Color(hex: 0x271A4F, alpha: 0xA6 / 255.0)
        public static let eventMeetingStroke = Color(hex: 0x9B72FF, alpha: 0x66 / 255.0)
        public static let eventProjectFill = Color(hex: 0x4D310B, alpha: 0xA6 / 255.0)
        public static let eventProjectStroke = Color(hex: 0xF7B955, alpha: 0x66 / 255.0)
        public static let eventPersonalFill = Color(hex: 0x12351F, alpha: 0xA6 / 255.0)
        public static let eventPersonalStroke = Color(hex: 0x37D67A, alpha: 0x66 / 255.0)
        public static let eventAdminFill = Color(hex: 0x1B2432, alpha: 0xA6 / 255.0)
        /// white at 1F/255 ≈ 0.12
        public static let eventAdminStroke = Color(hex: 0xFFFFFF, alpha: 0x1F / 255.0)
    }

    // MARK: Space

    public enum Space {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 6
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    // MARK: Radius

    public enum Radius {
        public static let xs: CGFloat = 6
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 22
        public static let window: CGFloat = 22
        public static let pill: CGFloat = 999
    }

    // MARK: Elevation

    public enum Elevation {
        public static let cardShadowRadius: CGFloat = 18
        public static let cardShadowY: CGFloat = 8
        public static let shellShadowRadius: CGFloat = 28
        public static let shellShadowY: CGFloat = 14
        public static let accentGlowRadius: CGFloat = 36
        public static let innerHighlightOpacity: Double = 0.68
        public static let rimHighlightOpacity: Double = 0.36
        public static let glassSheenOpacity: Double = 0.36
        public static let ambientPanelGlowOpacity: Double = 0.06
    }

    // MARK: Size

    public enum Size {
        public static let navItemHeight: CGFloat = 34
        public static let cardMinHeight: CGFloat = 120

        // macOS-only desktop window/chrome metrics.
        #if os(macOS)
        public static let sidebarWidth: CGFloat = 224
        public static let rightInspectorWidth: CGFloat = 304
        public static let toolbarHeight: CGFloat = 58
        public static let contentMinWidth: CGFloat = 760
        public static let windowMinWidth: CGFloat = 1180
        public static let windowIdealWidth: CGFloat = 1448
        public static let windowIdealHeight: CGFloat = 1086
        #endif
    }

    // MARK: FontToken

    public enum FontToken {
        public static let displayLarge = Font.system(size: 34, weight: .semibold, design: .serif)
        public static let displayMedium = Font.system(size: 28, weight: .semibold, design: .serif)
        public static let title = Font.system(size: 17, weight: .semibold)
        public static let section = Font.system(size: 14, weight: .semibold)
        public static let body = Font.system(size: 13, weight: .regular)
        public static let bodyStrong = Font.system(size: 13, weight: .semibold)
        public static let metadata = Font.system(size: 11, weight: .regular)
        public static let caption = Font.system(size: 10, weight: .medium)
        public static let button = Font.system(size: 13, weight: .semibold)
    }

    // MARK: Motion

    public enum Motion {
        public static let hover = Animation.easeOut(duration: 0.12)
        public static let press = Animation.easeOut(duration: 0.08)
        public static let panelReveal = Animation.easeInOut(duration: 0.20)
        public static let selection = Animation.easeInOut(duration: 0.16)
        /// view/destination transition
        public static let nav = Animation.smooth(duration: 0.28)
        /// general state change
        public static let standard = Animation.easeOut(duration: 0.22)
    }
}
