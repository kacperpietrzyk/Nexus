import AVFoundation
import Foundation

public enum AudioFileWriterError: Error {
    case formatUnavailable
    case tracksNotOpened
}

public final class AudioFileWriter: @unchecked Sendable {
    public let folder: URL
    private var meFile: AVAudioFile?
    private var othersFile: AVAudioFile?
    private let lock = NSLock()

    public init(folder: URL) throws {
        self.folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    public func openTracks() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let targetFormat = AudioFormat.target.makeAVAudioFormat() else {
            throw AudioFileWriterError.formatUnavailable
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioFormat.sampleRate,
            AVNumberOfChannelsKey: AudioFormat.channels,
            AVLinearPCMBitDepthKey: AudioFormat.bitsPerChannel,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let openedMeFile = try AVAudioFile(
            forWriting: folder.appendingPathComponent("me.wav"),
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        let openedOthersFile = try AVAudioFile(
            forWriting: folder.appendingPathComponent("others.wav"),
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        meFile = openedMeFile
        othersFile = openedOthersFile
        _ = targetFormat
    }

    public func writeMe(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let meFile else { throw AudioFileWriterError.tracksNotOpened }
        try meFile.write(from: buffer)
    }

    public func writeOthers(_ buffer: AVAudioPCMBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let othersFile else { throw AudioFileWriterError.tracksNotOpened }
        try othersFile.write(from: buffer)
    }

    public func finalize() throws {
        lock.lock()
        defer { lock.unlock() }
        meFile = nil
        othersFile = nil
    }

    public var meURL: URL { folder.appendingPathComponent("me.wav") }
    public var othersURL: URL { folder.appendingPathComponent("others.wav") }
}
