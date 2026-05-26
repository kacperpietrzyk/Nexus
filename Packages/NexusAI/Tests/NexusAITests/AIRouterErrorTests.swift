import Testing

@testable import NexusAI

@Test func aiRouterError_carriesProviderID_inConsentRequired() {
    let e = AIRouterError.consentRequired(.whisperKit)
    if case .consentRequired(let id) = e {
        #expect(id == .whisperKit)
    } else {
        Issue.record("expected .consentRequired")
    }
}

@Test func aiRouterError_carriesProviderID_inQuotaExceeded() {
    let e = AIRouterError.quotaExceeded(.whisperKit)
    if case .quotaExceeded(let id) = e {
        #expect(id == .whisperKit)
    } else {
        Issue.record("expected .quotaExceeded")
    }
}

@Test func aiRouterError_carriesProviderIDAndMessage_inRequestFailed() {
    let e = AIRouterError.requestFailed(.appleIntelligence, "lookup failed")
    if case .requestFailed(let id, let message) = e {
        #expect(id == .appleIntelligence)
        #expect(message == "lookup failed")
    } else {
        Issue.record("expected .requestFailed")
    }
}

@Test func aiRouterError_carriesCapability_inCapabilityNotSupported() {
    let e = AIRouterError.capabilityNotSupported(.longContext)
    if case .capabilityNotSupported(let cap) = e {
        #expect(cap == .longContext)
    } else {
        Issue.record("expected .capabilityNotSupported")
    }
}

@Test func aiRouterError_isEquatable() {
    #expect(AIRouterError.noProviderAvailable == AIRouterError.noProviderAvailable)
    #expect(
        AIRouterError.providerNotImplemented(.appleIntelligence)
            == AIRouterError.providerNotImplemented(.appleIntelligence))
    #expect(
        AIRouterError.providerNotImplemented(.appleIntelligence)
            != AIRouterError.providerNotImplemented(.whisperKit))
}
