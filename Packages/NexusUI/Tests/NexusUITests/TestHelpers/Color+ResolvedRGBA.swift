import SwiftUI

// swiftlint:disable large_tuple

#if canImport(AppKit)
import AppKit
extension Color {
    var resolvedRGBA: (r: Double, g: Double, b: Double, a: Double) {
        let ns = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent), Double(ns.alphaComponent))
    }
}
#elseif canImport(UIKit)
import UIKit
extension Color {
    var resolvedRGBA: (r: Double, g: Double, b: Double, a: Double) {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }
}
#endif

// swiftlint:enable large_tuple
