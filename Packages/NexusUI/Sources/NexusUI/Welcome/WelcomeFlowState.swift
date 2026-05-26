import Foundation
import Observation
import SwiftUI

#if !os(watchOS)

/// Drives the two-screen first-launch welcome flow. Mac and iOS only.
@MainActor
@Observable
public final class WelcomeFlowState {
    public static let totalScreens = 2

    public let totalScreenCount: Int
    public private(set) var currentScreen: Int = 0
    public private(set) var isFinished: Bool = false

    /// Chat model ID selected on the MLX welcome screen. Persisted via `persist()`.
    public var selectedChatModelID: String?
    /// Embedder model ID selected on the MLX welcome screen. Persisted via `persist()`.
    public var selectedEmbedderID: String?
    /// True when the user explicitly skipped on-device model setup. Persisted via `persist()`.
    public var skipMLX: Bool = false

    private let defaults: UserDefaults

    public init(extraScreenCount: Int = 0, defaults: UserDefaults = .standard) {
        totalScreenCount = Self.totalScreens + extraScreenCount
        self.defaults = defaults
        selectedChatModelID = defaults.string(forKey: NexusPreferences.Keys.selectedWelcomeChatModelID)
        selectedEmbedderID = defaults.string(forKey: NexusPreferences.Keys.selectedWelcomeEmbedderID)
        skipMLX = defaults.bool(forKey: NexusPreferences.Keys.skipWelcomeMLX)
    }

    public var isLastScreen: Bool {
        currentScreen == totalScreenCount - 1
    }

    public func advance() {
        if currentScreen < totalScreenCount - 1 {
            currentScreen += 1
        } else {
            isFinished = true
        }
    }

    public func skip() {
        isFinished = true
    }

    /// Writes the MLX model selection and skip flag to UserDefaults.
    /// Nil selections clear the stored key so a fresh load sees nil.
    public func persist() {
        if let id = selectedChatModelID {
            defaults.set(id, forKey: NexusPreferences.Keys.selectedWelcomeChatModelID)
        } else {
            defaults.removeObject(forKey: NexusPreferences.Keys.selectedWelcomeChatModelID)
        }
        if let id = selectedEmbedderID {
            defaults.set(id, forKey: NexusPreferences.Keys.selectedWelcomeEmbedderID)
        } else {
            defaults.removeObject(forKey: NexusPreferences.Keys.selectedWelcomeEmbedderID)
        }
        defaults.set(skipMLX, forKey: NexusPreferences.Keys.skipWelcomeMLX)
    }
}

#endif
