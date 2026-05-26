import SwiftUI

/// LabKit motion vocabulary. Restrained: easeOut, never bounce. Achromatic
/// system → motion carries state weight. Reduce Motion is gated inside the
/// modifiers in `NexusMotionModifiers.swift`, never at call sites.
public enum NexusMotion {
    public static let standard = Animation.easeOut(duration: 0.22)
    public static let hover = Animation.easeOut(duration: 0.12)
    public static let enter = Animation.easeOut(duration: 0.34)
    public static let exit = Animation.easeIn(duration: 0.16)
    public static let press = Animation.easeOut(duration: 0.12)
    public static let nav = Animation.smooth(duration: 0.28)
    public static let staggerStep = 0.055
    public static let breathePeriod = 2.4
}
