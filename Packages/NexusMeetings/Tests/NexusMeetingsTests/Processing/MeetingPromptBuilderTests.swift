import Foundation
import Testing

@testable import NexusMeetings

@Test func summaryPromptIncludesTranscript() {
    let prompt = MeetingPromptBuilder.summaryPrompt(
        transcript: "[00:00:00] Me\nCześć\n",
        title: "Daily standup",
        durationSec: 1_800,
        customTemplate: nil
    )
    #expect(prompt.contains("Daily standup"))
    #expect(prompt.contains("Cześć"))
    #expect(prompt.contains("TL;DR"))
}

@Test func actionItemsPromptAsksForJSON() {
    let prompt = MeetingPromptBuilder.actionItemsPrompt(
        transcript: "[00:00:00] Me\nI'll send the deck.\n",
        summary: "# Decisions"
    )
    #expect(prompt.contains("JSON"))
    #expect(prompt.contains("text"))
    #expect(prompt.contains("assigneeHint"))
}

@Test func customSummaryTemplateSubstitutesPlaceholders() {
    let prompt = MeetingPromptBuilder.summaryPrompt(
        transcript: "[00:00:00] Me\nPlan został zaakceptowany.\n",
        title: "Planning",
        durationSec: 900,
        customTemplate: "Title={{title}}\nMinutes={{durationMinutes}}\nBody={{transcript}}"
    )

    #expect(prompt.contains("Title=Planning"))
    #expect(prompt.contains("Minutes=15"))
    #expect(prompt.contains("Plan został zaakceptowany."))
}
