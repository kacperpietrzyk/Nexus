import Testing
@testable import NexusMeetings

@Suite struct AccessibilityPromptTests {
    @Test func promptsOnceWhenNotTrusted() {
        var prompts = 0
        var didPromptFlag = false
        let gate = AccessibilityPromptGate(
            isTrusted: { false },
            hasPrompted: { didPromptFlag },
            markPrompted: { didPromptFlag = true },
            prompt: { prompts += 1 }
        )
        gate.promptIfNeeded()
        gate.promptIfNeeded()
        #expect(prompts == 1)
    }

    @Test func neverPromptsWhenTrusted() {
        var prompts = 0
        let gate = AccessibilityPromptGate(
            isTrusted: { true },
            hasPrompted: { false },
            markPrompted: {},
            prompt: { prompts += 1 }
        )
        gate.promptIfNeeded()
        #expect(prompts == 0)
    }

    @Test func skipsWhenAlreadyPrompted() {
        var prompts = 0
        let gate = AccessibilityPromptGate(
            isTrusted: { false },
            hasPrompted: { true },
            markPrompted: {},
            prompt: { prompts += 1 }
        )
        gate.promptIfNeeded()
        #expect(prompts == 0)
    }
}
