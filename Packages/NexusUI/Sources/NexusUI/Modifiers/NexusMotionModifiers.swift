import SwiftUI

extension AnyTransition {
    public static var nexusView: AnyTransition {
        .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)), removal: .opacity)
    }
    public static var nexusToast: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity.combined(with: .offset(y: 6)))
    }
}

private struct NexusAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduce ? 0 : 6)
            .onAppear {
                let delay = reduce ? 0 : Double(index) * NexusMotion.staggerStep
                withAnimation(reduce ? NexusMotion.exit : NexusMotion.enter.delay(delay)) {
                    shown = true
                }
            }
    }
}

private struct NexusReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown || reduce ? 1 : 0.92)
            .onAppear {
                let delay = reduce ? 0 : 0.18 + Double(index) * 0.09
                withAnimation(reduce ? NexusMotion.exit : NexusMotion.standard.delay(delay)) {
                    shown = true
                }
            }
    }
}

public struct NexusPressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduce

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduce ? 0.97 : 1)
            .animation(NexusMotion.press, value: configuration.isPressed)
    }
}

private struct NexusPressable: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct NexusOverlayEnter: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduce ? 1 : 0.98)
            .opacity(shown ? 1 : 0)
            .onAppear { withAnimation(NexusMotion.standard) { shown = true } }
    }
}

extension View {
    public func nexusAppear(_ index: Int) -> some View { modifier(NexusAppear(index: index)) }
    public func nexusReveal(_ index: Int) -> some View { modifier(NexusReveal(index: index)) }
    public func nexusPressable() -> some View { modifier(NexusPressable()) }
    public func nexusOverlayEnter() -> some View { modifier(NexusOverlayEnter()) }
}
