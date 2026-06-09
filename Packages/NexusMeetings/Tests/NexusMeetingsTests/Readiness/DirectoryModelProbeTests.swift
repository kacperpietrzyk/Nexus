import Foundation
import Testing

@testable import NexusMeetings

@Suite("DirectoryModelProbe")
struct DirectoryModelProbeTests {
    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("reports ready + size when folder has a non-empty file, absent otherwise")
    func detectsPresence() throws {
        let present = try makeTempDir()
        try Data(repeating: 7, count: 16).write(to: present.appendingPathComponent("model.bin"))
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let probe = DirectoryModelProbe(
            resolvers: [
                .init(id: .parakeet, folder: { present }),
                .init(id: .sortformer, folder: { missing }),
                .init(id: .whisperKit, folder: { nil }),
            ],
            fileManager: .default
        )

        let result = probe.currentModels()
        let parakeet = try #require(result.first { $0.id == .parakeet })
        let sortformer = try #require(result.first { $0.id == .sortformer })
        let whisper = try #require(result.first { $0.id == .whisperKit })

        #expect(parakeet.downloaded)
        #expect(parakeet.state == .ready)
        #expect((parakeet.sizeBytes ?? 0) >= 16)
        #expect(!sortformer.downloaded)
        #expect(sortformer.state == .absent)
        #expect(!whisper.downloaded)
        #expect(whisper.state == .absent)
    }
}
