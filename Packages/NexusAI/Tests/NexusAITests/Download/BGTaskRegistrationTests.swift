import Foundation
import Testing
@testable import NexusAI

@Test func backgroundTaskIdentifierMatchesEntitlement() {
    #expect(ModelDownloadManager.backgroundTaskIdentifier == "com.kacperpietrzyk.nexus.modelDownload")
}
