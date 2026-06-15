import Testing

@testable import NexusUI

@MainActor
@Suite struct ProposalConfirmCardTests {
    @Test func acceptInvokesAsyncCallbackOnce() async {
        var accepted = 0
        let model = ProposalConfirmCardModel(
            title: "Refine title",
            rationale: "why",
            previews: ["old → new"],
            onAccept: { accepted += 1 },
            onReject: {}
        )
        await model.accept()
        #expect(accepted == 1)
        #expect(model.isApplying == false)  // resets after accept
    }

    @Test func rejectInvokesCallback() {
        var rejected = 0
        let model = ProposalConfirmCardModel(
            title: "t",
            rationale: "r",
            previews: [],
            onAccept: {},
            onReject: { rejected += 1 }
        )
        model.reject()
        #expect(rejected == 1)
    }
}
