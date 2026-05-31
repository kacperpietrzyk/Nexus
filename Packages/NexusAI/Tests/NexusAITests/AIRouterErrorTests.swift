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

@Test func aiRouterError_errorDescription_isUserFacingNotDebugFormat() {
    // requestFailed surfaces the carried message verbatim.
    #expect(
        AIRouterError.requestFailed(.appleIntelligence, "lookup failed").errorDescription
            == "lookup failed")
    // Provider-keyed cases name the provider in a human form (not the rawValue).
    let consent = try? #require(AIRouterError.consentRequired(.appleIntelligence).errorDescription)
    #expect(consent?.contains("Apple Intelligence") == true)
    #expect(consent?.contains("appleIntelligence") == false)
    let quota = AIRouterError.quotaExceeded(.appleIntelligence).errorDescription
    #expect(quota?.contains("Apple Intelligence") == true)
    // Every case yields a non-empty message (so `localizedDescription` is never
    // the generic "operation couldn't be completed" fallback).
    let all: [AIRouterError] = [
        .noProviderAvailable,
        .consentRequired(.appleIntelligence),
        .quotaExceeded(.appleIntelligence),
        .requestFailed(.mlx, "x"),
        .capabilityNotSupported(.longContext),
        .providerNotImplemented(.whisperKit),
    ]
    for error in all {
        #expect(error.errorDescription?.isEmpty == false)
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
