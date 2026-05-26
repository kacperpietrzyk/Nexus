import AVFoundation
import Foundation
import Testing

@testable import NexusMeetings

@Test func vadMeterRMSOnSilentBuffer() {
    let meter = VADMeter()
    let format = AudioFormat.target.makeAVAudioFormat()!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600

    let level = meter.rmsLevel(buffer)

    #expect(level <= 0.001)
}

@Test func vadMeterRMSOnFullScaleBuffer() {
    let meter = VADMeter()
    let format = AudioFormat.target.makeAVAudioFormat()!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    if let data = buffer.int16ChannelData {
        for index in 0..<Int(buffer.frameLength) {
            data[0][index] = Int16.max
        }
    }

    let level = meter.rmsLevel(buffer)

    #expect(level >= 0.95)
}

@Test func vadMeterRMSOnEmptyBuffer() {
    let meter = VADMeter()
    let format = AudioFormat.target.makeAVAudioFormat()!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 0

    let level = meter.rmsLevel(buffer)

    #expect(level == 0)
}

@Test func vadMeterRMSOnFloatBuffer() {
    let meter = VADMeter()
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioFormat.sampleRate,
        channels: AudioFormat.channels,
        interleaved: false
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
    buffer.frameLength = 1_600
    if let data = buffer.floatChannelData {
        for index in 0..<Int(buffer.frameLength) {
            data[0][index] = 1
        }
    }

    let level = meter.rmsLevel(buffer)

    #expect(level >= 0.95)
}
