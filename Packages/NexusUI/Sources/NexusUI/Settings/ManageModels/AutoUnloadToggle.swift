import SwiftUI

#if !os(watchOS)

public struct AutoUnloadToggle: View {
    @AppStorage(NexusPreferences.Keys.mlxAutoUnloadEnabled) private var enabled = true

    public init() {}

    public var body: some View {
        Toggle("Auto-unload idle models", isOn: $enabled)
            .help(
                "iOS unloads after 2 min idle; Mac after 10 min. "
                    + "Disabling keeps models always-resident at the cost of RAM."
            )
    }
}

public struct PreloadChatToggle: View {
    @AppStorage(NexusPreferences.Keys.mlxPreloadChat) private var preload = false

    public init() {}

    public var body: some View {
        Toggle("Preload chat model on launch", isOn: $preload)
            .help(
                "Loads the assigned chat model at app start so the first message has zero latency."
            )
    }
}

#endif
