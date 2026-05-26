import Foundation
import Testing

@testable import NexusAgent

@Test func inputBarDisablesSendWhenEmpty() {
    #expect(!AgentInputBar.shouldEnableSend(input: ""))
    #expect(!AgentInputBar.shouldEnableSend(input: "   \n\t  "))
    #expect(AgentInputBar.shouldEnableSend(input: "hello"))
}

@Test func inputBarDisablesSendWhileBusyOrLocalSendInFlight() {
    #expect(!AgentInputBar.shouldEnableSend(input: "hello", isThinking: true))
    #expect(!AgentInputBar.shouldEnableSend(input: "hello", isSending: true))
    #expect(AgentInputBar.shouldEnableSend(input: "hello"))
}

@Test func inputBarTrimsWhitespaceBeforeSending() {
    #expect(AgentInputBar.normalize("  hi  ") == "hi")
    #expect(AgentInputBar.normalize("\nmulti\nline\n") == "multi\nline")
}

@Test func inputBarAppendsVoiceTranscriptWithoutSending() {
    #expect(AgentInputBar.appendTranscript(" voice ", to: "") == "voice")
    #expect(AgentInputBar.appendTranscript("voice", to: "Ask") == "Ask voice")
    #expect(AgentInputBar.appendTranscript("   ", to: "Ask") == "Ask")
}

@Test func inputBarDisablesVoiceButtonForUnavailableOrRunningStates() {
    #expect(AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: false))
    #expect(AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: true, isVoiceCaptureAvailable: false))
    #expect(AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: true, isThinking: true))
    #expect(AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: true, isVoiceStarting: true))
    #expect(AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: true, hasActiveVoiceSession: true))
    #expect(AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: true, isVoiceTranscribing: true))
    #expect(!AgentInputBar.shouldDisableVoiceButton(hasVoiceCapture: true, isVoiceCaptureAvailable: true))
}

@Test func inputBarDisablesImageButtonWithoutAvailableCloudVision() {
    #expect(AgentInputBar.shouldDisableImageButton(isImageCaptureAvailable: false))
    #expect(AgentInputBar.shouldDisableImageButton(isImageCaptureAvailable: true, isThinking: true))
    #expect(!AgentInputBar.shouldDisableImageButton(isImageCaptureAvailable: true))
}

@Test func inputBarDisablesImageDropTargetingWithoutAvailableVision() {
    #expect(!AgentInputBar.shouldEnableImageDropTargeting(isImageCaptureAvailable: false))
    #expect(!AgentInputBar.shouldEnableImageDropTargeting(isImageCaptureAvailable: true, isThinking: true))
    #expect(!AgentInputBar.shouldEnableImageDropTargeting(isImageCaptureAvailable: true, isSending: true))
    #expect(AgentInputBar.shouldEnableImageDropTargeting(isImageCaptureAvailable: true))
}

@Test func inputBarEnablesImageButtonWhenVisionAvailable() {
    #expect(AgentInputBar.shouldDisableImageButton(isImageCaptureAvailable: true, isThinking: false) == false)
}

@Test func inputBarEnablesImageDropTargetingWhenVisionAvailable() {
    #expect(AgentInputBar.shouldEnableImageDropTargeting(isImageCaptureAvailable: true) == true)
}

@Test func inputBarClearsImageDropTargetingWhenGateDisables() {
    #expect(AgentInputBar.shouldClearImageDropTargeting(isTargeted: true, isImageDropTargetingEnabled: false))
    #expect(!AgentInputBar.shouldClearImageDropTargeting(isTargeted: true, isImageDropTargetingEnabled: true))
    #expect(!AgentInputBar.shouldClearImageDropTargeting(isTargeted: false, isImageDropTargetingEnabled: false))
}

@Test func inputBarLocalizesImageAttachmentDeferralBannerCopy() {
    #expect(
        AgentInputBar.localizedImageDeferralMessage(
            reason: .pendingLocalAIPhase,
            locale: Locale(identifier: "en_US")
        )
            == "Image attachments arrive with on-device AI in the next phase."
    )
    #expect(
        AgentInputBar.localizedImageDeferralMessage(
            reason: .pendingLocalAIPhase,
            locale: Locale(identifier: "pl_PL")
        )
            == "Załączniki obrazów pojawią się wraz z lokalnym modelem w kolejnej fazie."
    )
}

@Test func inputBarAcceptsOnlyFileURLsFromDropProviderItems() {
    let fileURL = URL(filePath: "/tmp/context.txt")

    #expect(AgentInputBar.fileURL(fromProviderItem: fileURL as NSURL) == fileURL)
    #expect(AgentInputBar.fileURL(fromProviderItem: fileURL.absoluteString as NSString) == fileURL)
    #expect(AgentInputBar.fileURL(fromProviderItem: "https://example.com/context.txt" as NSString) == nil)
}
