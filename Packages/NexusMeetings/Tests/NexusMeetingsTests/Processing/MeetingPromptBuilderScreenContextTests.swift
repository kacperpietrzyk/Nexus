import Foundation
import Testing

@testable import NexusMeetings

struct MeetingPromptBuilderScreenContextTests {
    @Test func summaryPromptUnchangedWhenScreenContextNil() {
        let withoutArg = MeetingPromptBuilder.summaryPrompt(
            transcript: "hello",
            title: "Sync",
            durationSec: 600,
            customTemplate: nil
        )
        let withNil = MeetingPromptBuilder.summaryPrompt(
            transcript: "hello",
            title: "Sync",
            durationSec: 600,
            customTemplate: nil,
            screenContext: nil
        )
        #expect(withoutArg == withNil)
        #expect(withNil.contains("On-screen context") == false)
    }

    @Test func summaryPromptInjectsScreenContext() {
        let prompt = MeetingPromptBuilder.summaryPrompt(
            transcript: "hello",
            title: "Sync",
            durationSec: 600,
            customTemplate: nil,
            screenContext: "Roadmap slide: Q3 launch"
        )
        #expect(prompt.contains("On-screen context"))
        #expect(prompt.contains("Roadmap slide: Q3 launch"))
    }

    @Test func actionItemsPromptUnchangedWhenScreenContextNil() {
        let withoutArg = MeetingPromptBuilder.actionItemsPrompt(transcript: "t", summary: "s")
        let withNil = MeetingPromptBuilder.actionItemsPrompt(
            transcript: "t",
            summary: "s",
            screenContext: nil
        )
        #expect(withoutArg == withNil)
        #expect(withNil.contains("On-screen context") == false)
    }

    @Test func actionItemsPromptInjectsScreenContext() {
        let prompt = MeetingPromptBuilder.actionItemsPrompt(
            transcript: "t",
            summary: "s",
            screenContext: "Jira board: TASK-42"
        )
        #expect(prompt.contains("On-screen context"))
        #expect(prompt.contains("Jira board: TASK-42"))
    }

    @Test func customTemplateScreenContextPlaceholderIsFilled() {
        let prompt = MeetingPromptBuilder.summaryPrompt(
            transcript: "T",
            title: "X",
            durationSec: 60,
            customTemplate: "ctx={{screenContext}}",
            screenContext: "VISIBLE"
        )
        #expect(prompt == "ctx=VISIBLE")
    }

    @Test func customTemplateScreenContextPlaceholderEmptyWhenNil() {
        let prompt = MeetingPromptBuilder.summaryPrompt(
            transcript: "T",
            title: "X",
            durationSec: 60,
            customTemplate: "ctx={{screenContext}}",
            screenContext: nil
        )
        #expect(prompt == "ctx=")
    }
}
