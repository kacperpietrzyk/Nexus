import Foundation
import Testing

@testable import NexusAI

@Test func providerID_rawValues_areStableLowercaseStrings() {
    #expect(ProviderID.appleIntelligence.rawValue == "appleIntelligence")
    #expect(ProviderID.whisperKit.rawValue == "whisperKit")
    #expect(ProviderID.mlx.rawValue == "mlx")
}

@Test func providerID_isCodable() throws {
    let all: [ProviderID] = [.appleIntelligence, .whisperKit, .mlx]
    let data = try JSONEncoder().encode(all)
    let decoded = try JSONDecoder().decode([ProviderID].self, from: data)
    #expect(decoded == all)
}

@Test func providerID_allCases_haveStableOrder() {
    #expect(
        ProviderID.allCases == [.appleIntelligence, .whisperKit, .mlx]
    )
}

@Test func providerID_mlx_isOnDevice() {
    #expect(ProviderID.mlx.isOnDevice)
}
