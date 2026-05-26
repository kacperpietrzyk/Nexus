import SwiftUI

extension Color {
    /// Internal hex initializer — used by token definitions only.
    /// Accepts 24-bit RGB packed as `0xRRGGBB`. Alpha defaults to 1.0.
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
