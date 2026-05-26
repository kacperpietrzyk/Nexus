import Combine
import SwiftUI

@MainActor
public final class MeetingsDetectionSettingsViewModel: ObservableObject {
    @Published public private(set) var registry: AppPatternRegistry

    private let store: any AppPatternRegistryStoring

    public init(store: any AppPatternRegistryStoring = UserDefaultsAppPatternRegistryStore.shared) {
        self.store = store
        registry = store.load()
    }

    public func toggle(bundleID: String, enabled: Bool) {
        registry.setEnabled(bundleID, enabled: enabled)
        store.save(registry)
    }

    public func append(_ pattern: AppPattern) {
        registry.append(pattern)
        store.save(registry)
    }
}

public struct MeetingsDetectionSettingsView: View {
    private let composition: MeetingsComposition
    @StateObject private var viewModel: MeetingsDetectionSettingsViewModel

    public init(
        composition: MeetingsComposition,
        store: any AppPatternRegistryStoring = UserDefaultsAppPatternRegistryStore.shared
    ) {
        self.composition = composition
        _viewModel = StateObject(
            wrappedValue: MeetingsDetectionSettingsViewModel(store: store)
        )
    }

    public var body: some View {
        Section("Tracked apps") {
            ForEach(viewModel.registry.patterns, id: \.bundleID) { pattern in
                Toggle(
                    pattern.displayName,
                    isOn: Binding(
                        get: { pattern.enabled },
                        set: { enabled in
                            viewModel.toggle(bundleID: pattern.bundleID, enabled: enabled)
                        }
                    )
                )
            }
        }
    }
}
