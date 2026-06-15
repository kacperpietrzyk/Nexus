import Testing

@testable import NexusUI

@Test func settingsCategoriesAreTheSevenConsolidatedGroupsInOrder() {
    #expect(
        SettingsCategory.allCases == [
            .general, .sync, .tasks, .aiModels, .meetings, .advanced, .about,
        ])
    #expect(SettingsCategory.general.title == "General")
    #expect(SettingsCategory.aiModels.title == "AI & Models")
}
