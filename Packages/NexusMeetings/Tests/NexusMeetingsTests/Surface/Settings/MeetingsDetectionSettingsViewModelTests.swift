import Testing

@testable import NexusMeetings

@MainActor
@Test func detectionViewModelTogglesPattern() {
    let store = AppPatternRegistryStoreInMemory(initial: .makeDefault())
    let vm = MeetingsDetectionSettingsViewModel(store: store)
    let registry = vm.registry
    let teams = registry.patterns.first { $0.bundleID == "com.microsoft.teams2" }!
    #expect(teams.enabled == true)

    vm.toggle(bundleID: "com.microsoft.teams2", enabled: false)

    #expect(vm.registry.patterns.first(where: { $0.bundleID == "com.microsoft.teams2" })?.enabled == false)
}

@MainActor
@Test func detectionViewModelLoadsSavedRegistryFromStore() {
    let store = AppPatternRegistryStoreInMemory(initial: .makeDefault())
    let firstVM = MeetingsDetectionSettingsViewModel(store: store)
    firstVM.toggle(bundleID: "com.microsoft.teams2", enabled: false)

    let secondVM = MeetingsDetectionSettingsViewModel(store: store)

    #expect(secondVM.registry.patterns.first(where: { $0.bundleID == "com.microsoft.teams2" })?.enabled == false)
}

private final class AppPatternRegistryStoreInMemory: AppPatternRegistryStoring, @unchecked Sendable {
    var current: AppPatternRegistry

    init(initial: AppPatternRegistry) {
        current = initial
    }

    func load() -> AppPatternRegistry {
        current
    }

    func save(_ registry: AppPatternRegistry) {
        current = registry
    }
}
