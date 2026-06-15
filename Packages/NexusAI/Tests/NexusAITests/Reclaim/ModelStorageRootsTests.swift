import Foundation
import Testing

@testable import NexusAI

@Suite struct ModelStorageRootsTests {
    @Test func productionRootsHaveExpectedSuffixes() {
        let roots = ModelStorageRoots.production()
        #expect(roots.managedModels.path.hasSuffix("Nexus/Models"))
        #expect(roots.stagingCache.path.hasSuffix("Nexus/Models/.hf-cache"))
        #expect(roots.hubCache.path.hasSuffix("huggingface/hub"))
        #expect(roots.whisperKit.path.hasSuffix("Nexus/WhisperKit/models/argmaxinc/whisperkit-coreml"))
    }
}
