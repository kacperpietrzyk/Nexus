import AVFoundation
import Foundation

public enum AudioFormat {
    public static let sampleRate: Double = 16_000
    public static let channels: AVAudioChannelCount = 1
    public static let bitsPerChannel: UInt32 = 16

    public static var target: AudioFormatSpec {
        AudioFormatSpec(sampleRate: sampleRate, channels: channels, bitsPerChannel: bitsPerChannel)
    }
}

public struct AudioFormatSpec: Sendable {
    public let sampleRate: Double
    public let channels: AVAudioChannelCount
    public let bitsPerChannel: UInt32

    public func makeAVAudioFormat() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true
        )
    }
}
