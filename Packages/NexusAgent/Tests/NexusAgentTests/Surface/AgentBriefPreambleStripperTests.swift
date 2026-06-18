import Testing

@testable import NexusAgent

@Suite("AgentBriefService.strippingLeadingPreamble")
struct AgentBriefPreambleStripperTests {
    // Known leaked preamble on the same line as the body (the observed regression).
    @Test
    func stripsHereIsOnSameLine() {
        let input = "Here is a brief for the user based on their real tasks: Three things matter today."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == "Three things matter today.")
    }

    // "Here's" contraction variant.
    @Test
    func stripsHeresContraction() {
        let input = "Here's your daily brief: Two tasks need attention today."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == "Two tasks need attention today.")
    }

    // "Below is" variant.
    @Test
    func stripsBelowIsSummary() {
        let input = "Below is a summary of your day: Focus on the review first."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == "Focus on the review first.")
    }

    // Preamble on its own line, body on the next.
    @Test
    func stripsStandalonePreambleLine() {
        let input = "Here is today's brief:\nThree things matter today."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == "Three things matter today.")
    }

    // Clean brief must be returned unchanged.
    @Test
    func leavesCleanBriefUntouched() {
        let input = "Three things matter today — ship the review, close the sprint, prep the demo."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == input)
    }

    // Body that contains an internal colon must not be over-stripped.
    @Test
    func doesNotOverStripBodyWithInternalColon() {
        let input = "Focus areas: review and planning. Two tasks are overdue."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == input)
    }

    // "This is" variant.
    @Test
    func stripsThisIsBrief() {
        let input = "This is your brief for today: Ship the feature and review the PR."
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == "Ship the feature and review the PR.")
    }

    // A brief that starts with "Plan:" (regression guard from identity-stable test).
    @Test
    func doesNotStripPlanColon() {
        let input = "Plan:\n- [ ] Ship it"
        let result = AgentBriefService.strippingLeadingPreamble(from: input)
        #expect(result == input)
    }
}
