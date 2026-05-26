import AVFoundation
import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func writerProducesTwoNonEmptyFiles() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mw-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let writer = try AudioFileWriter(folder: dir)
    try writer.openTracks()

    let format = AudioFormat.target.makeAVAudioFormat()!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    if let data = buffer.int16ChannelData {
        for i in 0..<Int(buffer.frameLength) { data[0][i] = Int16(i % 1_000) }
    }
    try writer.writeMe(buffer)
    try writer.writeOthers(buffer)
    try writer.finalize()

    let me = dir.appendingPathComponent("me.wav")
    let others = dir.appendingPathComponent("others.wav")
    let meSize = try #require(
        FileManager.default.attributesOfItem(atPath: me.path)[.size] as? Int64
    )
    let othersSize = try #require(
        FileManager.default.attributesOfItem(atPath: others.path)[.size] as? Int64
    )
    #expect(meSize > 0)
    #expect(othersSize > 0)

    try assertTargetFormat(at: me)
    try assertTargetFormat(at: others)
}

@MainActor
@Test func writerRejectsWritesBeforeOpen() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mw-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let writer = try AudioFileWriter(folder: dir)
    let format = AudioFormat.target.makeAVAudioFormat()!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
    buffer.frameLength = 1

    do {
        try writer.writeMe(buffer)
        Issue.record("Expected writeMe before openTracks to throw")
    } catch AudioFileWriterError.tracksNotOpened {}

    do {
        try writer.writeOthers(buffer)
        Issue.record("Expected writeOthers before openTracks to throw")
    } catch AudioFileWriterError.tracksNotOpened {}
}

private func assertTargetFormat(at url: URL) throws {
    let file = try AVAudioFile(forReading: url)
    let settings = file.fileFormat.settings

    #expect(file.fileFormat.sampleRate == AudioFormat.sampleRate)
    #expect(file.fileFormat.channelCount == AudioFormat.channels)
    #expect(intSetting(settings, AVFormatIDKey) == Int(kAudioFormatLinearPCM))
    #expect(intSetting(settings, AVNumberOfChannelsKey) == Int(AudioFormat.channels))
    #expect(intSetting(settings, AVLinearPCMBitDepthKey) == Int(AudioFormat.bitsPerChannel))
    #expect(boolSetting(settings, AVLinearPCMIsFloatKey) == false)
    #expect(boolSetting(settings, AVLinearPCMIsBigEndianKey) == false)
}

private func intSetting(_ settings: [String: Any], _ key: String) -> Int? {
    (settings[key] as? NSNumber)?.intValue
}

private func boolSetting(_ settings: [String: Any], _ key: String) -> Bool? {
    (settings[key] as? NSNumber)?.boolValue
}
