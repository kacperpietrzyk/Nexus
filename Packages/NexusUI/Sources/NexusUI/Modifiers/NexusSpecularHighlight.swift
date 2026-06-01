import SwiftUI

/// Specular highlight modifier — neutralized for Linear "Midnight Command
/// Center". Linear surfaces are flat, so this is now a no-op on every platform:
/// it returns `content` unchanged. The modifier name, public init, and the
/// `tintColor` / `defaultRadius` constants are retained so call sites compile
/// and the frozen-API tests keep passing (the body no longer reads them).
public struct NexusSpecularHighlight: ViewModifier {

    public static let tintColor: Color = NexusColor.Glass.surface3
    public static let defaultRadius: CGFloat = 220

    public init() {}

    public func body(content: Content) -> some View {
        content
    }
}

extension View {
    /// Mac-only cursor-tracked specular highlight. No-ops on every other platform.
    public func nexusSpecularHighlight() -> some View {
        modifier(NexusSpecularHighlight())
    }
}
