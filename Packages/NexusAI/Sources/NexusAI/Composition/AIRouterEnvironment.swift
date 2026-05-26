import SwiftUI

private struct AIRouterKey: EnvironmentKey {
    static let defaultValue: AIRouter? = nil
}

extension EnvironmentValues {
    public var aiRouter: AIRouter? {
        get { self[AIRouterKey.self] }
        set { self[AIRouterKey.self] = newValue }
    }
}
