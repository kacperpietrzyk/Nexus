import Combine
import NexusUI
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
        LiquidGlassCard("Tracked apps") {
            if viewModel.registry.patterns.isEmpty {
                NexusEmptyState(
                    systemImage: "app.dashed",
                    title: "No tracked apps yet."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(viewModel.registry.patterns.enumerated()), id: \.element.bundleID) { index, pattern in
                        if index > 0 {
                            Divider()
                                .overlay(DS.ColorToken.strokeHairline)
                        }
                        HStack {
                            Text(pattern.displayName)
                                .font(DS.FontToken.body)
                                .foregroundStyle(DS.ColorToken.textPrimary)
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { pattern.enabled },
                                    set: { enabled in
                                        viewModel.toggle(bundleID: pattern.bundleID, enabled: enabled)
                                    }
                                )
                            )
                            .labelsHidden()
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
    }
}
