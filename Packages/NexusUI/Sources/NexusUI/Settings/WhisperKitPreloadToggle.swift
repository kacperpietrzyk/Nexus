import SwiftUI

#if !os(watchOS)

public struct WhisperKitPreloadToggle: View {
    @AppStorage(NexusPreferences.Keys.agentVoicePreloadWhisperKit) private var enabled = false

    public init() {}

    public var body: some View {
        Toggle("Preload transcription model at launch", isOn: $enabled)
            .help(
                "Loads the WhisperKit model on app start so the first voice tap is instant. "
                    + "Costs RAM and a few seconds at launch."
            )
    }
}

#endif
