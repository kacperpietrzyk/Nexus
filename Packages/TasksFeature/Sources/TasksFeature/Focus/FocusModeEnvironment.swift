import SwiftUI

private struct FocusModeStateEnvironmentKey: EnvironmentKey {
    static let defaultValue: FocusModeState? = nil
}

extension EnvironmentValues {
    /// Injected by app composition roots. Views consume via
    /// `@Environment(\.focusModeState)`. Default `nil` means the host app
    /// did not enable focus mode; focus entry actions become no-ops in that case.
    public var focusModeState: FocusModeState? {
        get { self[FocusModeStateEnvironmentKey.self] }
        set { self[FocusModeStateEnvironmentKey.self] = newValue }
    }
}
