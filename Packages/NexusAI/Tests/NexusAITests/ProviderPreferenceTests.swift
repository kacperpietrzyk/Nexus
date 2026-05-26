import Testing

@testable import NexusAI

@Test func providerPreference_allCases_excludesClaudePreferences() {
    let rawValues = ProviderPreference.allCases.map(\.rawValue)

    #expect(!rawValues.contains("claude"))
    #expect(!rawValues.contains("claude" + "shell"))
    #expect(rawValues == ["auto"])
}
