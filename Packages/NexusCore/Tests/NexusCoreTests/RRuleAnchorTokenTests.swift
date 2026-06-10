import Foundation
import Testing

@testable import NexusCore

@Suite("RRuleAnchorToken")
struct RRuleAnchorTokenTests {
    @Test("detects the completion anchor case-insensitively")
    func detection() {
        #expect(RRuleAnchorToken.isCompletionAnchored("FREQ=DAILY;ANCHOR=COMPLETION"))
        #expect(RRuleAnchorToken.isCompletionAnchored("freq=daily;anchor=completion"))
        #expect(!RRuleAnchorToken.isCompletionAnchored("FREQ=DAILY"))
        #expect(!RRuleAnchorToken.isCompletionAnchored("FREQ=DAILY;ANCHOR=DUE"))
        #expect(!RRuleAnchorToken.isCompletionAnchored(""))
    }

    @Test("strippingAnchor removes only the ANCHOR token")
    func stripping() {
        #expect(RRuleAnchorToken.strippingAnchor("FREQ=DAILY;ANCHOR=COMPLETION") == "FREQ=DAILY")
        #expect(
            RRuleAnchorToken.strippingAnchor("FREQ=WEEKLY;BYDAY=MO;ANCHOR=COMPLETION")
                == "FREQ=WEEKLY;BYDAY=MO")
        #expect(RRuleAnchorToken.strippingAnchor("ANCHOR=COMPLETION;FREQ=DAILY") == "FREQ=DAILY")
        #expect(RRuleAnchorToken.strippingAnchor("FREQ=DAILY") == "FREQ=DAILY")
        #expect(RRuleAnchorToken.strippingAnchor("").isEmpty)
    }

    @Test("applying toggles the anchor without disturbing other tokens")
    func applying() {
        #expect(
            RRuleAnchorToken.applying(completionAnchor: true, to: "FREQ=DAILY")
                == "FREQ=DAILY;ANCHOR=COMPLETION")
        #expect(
            RRuleAnchorToken.applying(completionAnchor: false, to: "FREQ=DAILY;ANCHOR=COMPLETION")
                == "FREQ=DAILY")
        #expect(
            RRuleAnchorToken.applying(completionAnchor: true, to: "FREQ=DAILY;ANCHOR=COMPLETION")
                == "FREQ=DAILY;ANCHOR=COMPLETION")
        #expect(RRuleAnchorToken.applying(completionAnchor: true, to: "").isEmpty)
    }
}
