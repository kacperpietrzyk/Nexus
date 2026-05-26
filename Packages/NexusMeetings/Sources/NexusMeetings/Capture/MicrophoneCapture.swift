import AVFoundation
import Foundation

public enum AudioCaptureError: Error {
    case converterUnavailable
    case outputBufferUnavailable
    case conversionFailedWithoutError
    case bufferCopyUnavailable
}

public final class MicrophoneCapture: @unchecked Sendable {
    private let writer: AudioFileWriter
    private let targetFormat: AVAudioFormat
    private let meter = VADMeter()
    private var engine: AVAudioEngine?
    private let converterQueue = DispatchQueue(label: "nexus.meetings.mic.converter")
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?
    private let errorLock = NSLock()
    private var lastError: (any Error)?
    private let onError: (@Sendable (any Error) -> Void)?
    private let levelSink: (@Sendable (Float) -> Void)?

    public init(
        writer: AudioFileWriter,
        onError: (@Sendable (any Error) -> Void)? = nil,
        levelSink: (@Sendable (Float) -> Void)? = nil
    ) {
        self.writer = writer
        self.targetFormat = AudioFormat.target.makeAVAudioFormat()!
        self.onError = onError
        self.levelSink = levelSink
    }

    public func start() throws {
        let engine = AVAudioEngine()
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
            self?.enqueue(rawBuffer: buffer)
        }
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            throw error
        }
        self.engine = engine
    }

    public func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        finishPendingWrites()
    }

    public func finishPendingWrites() {
        converterQueue.sync {}
    }

    public func consumeLastError() -> (any Error)? {
        errorLock.lock()
        defer { errorLock.unlock() }
        let error = lastError
        lastError = nil
        return error
    }

    public func handle(rawBuffer: AVAudioPCMBuffer) throws {
        levelSink?(meter.rmsLevel(rawBuffer))
        try converterQueue.sync {
            try convertAndWrite(rawBuffer)
        }
    }

    private func enqueue(rawBuffer: AVAudioPCMBuffer) {
        levelSink?(meter.rmsLevel(rawBuffer))
        do {
            let queuedBuffer = CaptureAudioQueuedBuffer(try rawBuffer.copyForCaptureQueue())
            converterQueue.async {
                do {
                    try self.convertAndWrite(queuedBuffer.buffer)
                } catch {
                    self.record(error: error)
                }
            }
        } catch {
            record(error: error)
        }
    }

    private func convertAndWrite(_ rawBuffer: AVAudioPCMBuffer) throws {
        let sourceFormat = rawBuffer.format
        if converter == nil || converterSourceFormat != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            converterSourceFormat = sourceFormat
        }
        guard let converter else {
            throw AudioCaptureError.converterUnavailable
        }
        let outputCapacity =
            AVAudioFrameCount(
                Double(rawBuffer.frameLength) * (targetFormat.sampleRate / sourceFormat.sampleRate)
            ) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputCapacity) else {
            throw AudioCaptureError.outputBufferUnavailable
        }
        var error: NSError?
        let input = CaptureAudioConverterInputBuffer(rawBuffer)
        let status = converter.convert(to: outputBuffer, error: &error) { _, status in
            input.next(status: status)
        }
        if status == .error {
            if let error { throw error }
            throw AudioCaptureError.conversionFailedWithoutError
        }
        try writer.writeMe(outputBuffer)
    }

    private func record(error: any Error) {
        errorLock.lock()
        lastError = error
        errorLock.unlock()
        onError?(error)
    }
}

extension AVAudioPCMBuffer {
    func copyForCaptureQueue() throws -> AVAudioPCMBuffer {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            throw AudioCaptureError.bufferCopyUnavailable
        }
        copy.frameLength = frameLength

        let channelCount = format.isInterleaved ? 1 : Int(format.channelCount)
        let samplesPerChannel = Int(frameLength) * (format.isInterleaved ? Int(format.channelCount) : 1)

        switch format.commonFormat {
        case .pcmFormatFloat32:
            try copySamples(source: floatChannelData, destination: copy.floatChannelData, channelCount, samplesPerChannel)
        case .pcmFormatFloat64:
            throw AudioCaptureError.bufferCopyUnavailable
        case .pcmFormatInt16:
            try copySamples(source: int16ChannelData, destination: copy.int16ChannelData, channelCount, samplesPerChannel)
        case .pcmFormatInt32:
            try copySamples(source: int32ChannelData, destination: copy.int32ChannelData, channelCount, samplesPerChannel)
        case .otherFormat:
            throw AudioCaptureError.bufferCopyUnavailable
        @unknown default:
            throw AudioCaptureError.bufferCopyUnavailable
        }
        return copy
    }

    private func copySamples<T>(
        source: UnsafePointer<UnsafeMutablePointer<T>>?,
        destination: UnsafePointer<UnsafeMutablePointer<T>>?,
        _ channelCount: Int,
        _ samplesPerChannel: Int
    ) throws {
        guard let source, let destination else {
            throw AudioCaptureError.bufferCopyUnavailable
        }
        for channel in 0..<channelCount {
            let sourceChannel = source[channel]
            let destinationChannel = destination[channel]
            destinationChannel.update(from: sourceChannel, count: samplesPerChannel)
        }
    }
}

final class CaptureAudioQueuedBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

final class CaptureAudioConverterInputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var consumed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        if consumed {
            status.pointee = .noDataNow
            return nil
        }
        consumed = true
        status.pointee = .haveData
        return buffer
    }
}
