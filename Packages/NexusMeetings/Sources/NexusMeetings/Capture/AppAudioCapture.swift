import AVFoundation
import CoreAudio
import Foundation

public protocol AppAudioTapping: Sendable {
    func start(pid: pid_t) throws
    func stop()
}

public struct NoopAppAudioTap: AppAudioTapping {
    public init() {}
    public func start(pid: pid_t) throws {}
    public func stop() {}
}

public final class AppAudioCapture: @unchecked Sendable {
    private let writer: AudioFileWriter
    private let targetFormat: AVAudioFormat
    private let tap: any AppAudioTapping
    private let meter = VADMeter()
    private let converterQueue = DispatchQueue(label: "nexus.meetings.app.converter")
    private var converter: AVAudioConverter?
    private var converterSourceFormat: AVAudioFormat?
    private let levelSink: (@Sendable (Float) -> Void)?
    private let pausedLock = NSLock()
    private var paused = false

    public init(
        writer: AudioFileWriter,
        tap: any AppAudioTapping,
        levelSink: (@Sendable (Float) -> Void)? = nil
    ) {
        self.writer = writer
        self.targetFormat = AudioFormat.target.makeAVAudioFormat()!
        self.tap = tap
        self.levelSink = levelSink
    }

    public func start(pid: pid_t) throws {
        try tap.start(pid: pid)
    }

    public func stop() {
        tap.stop()
        finishPendingWrites()
    }

    public func finishPendingWrites() {
        converterQueue.sync {}
    }

    /// Suspend/resume writing without destroying the process tap: while paused
    /// the tapped buffers are dropped (the file gets a silent gap), so resuming
    /// continues the same file.
    public func setPaused(_ paused: Bool) {
        pausedLock.lock()
        self.paused = paused
        pausedLock.unlock()
    }

    private var isPaused: Bool {
        pausedLock.lock()
        defer { pausedLock.unlock() }
        return paused
    }

    public func handle(rawBuffer: AVAudioPCMBuffer) throws {
        guard isPaused == false else { return }
        levelSink?(meter.rmsLevel(rawBuffer))
        try converterQueue.sync {
            try convertAndWrite(rawBuffer)
        }
    }

    public func enqueue(rawBuffer: AVAudioPCMBuffer, onError: (@Sendable (any Error) -> Void)? = nil) {
        guard isPaused == false else { return }
        levelSink?(meter.rmsLevel(rawBuffer))
        do {
            let queuedBuffer = CaptureAudioQueuedBuffer(try rawBuffer.copyForCaptureQueue())
            converterQueue.async {
                do {
                    try self.convertAndWrite(queuedBuffer.buffer)
                } catch {
                    onError?(error)
                }
            }
        } catch {
            onError?(error)
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
        try writer.writeOthers(outputBuffer)
    }
}

#if os(macOS) && canImport(CoreAudio)
public final class CATapAppAudioTap: AppAudioTapping, @unchecked Sendable {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void
    private let ioQueue = DispatchQueue(label: "nexus.meetings.catap.ioproc")
    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioObjectID = 0
    private var deviceProcID: AudioDeviceIOProcID?

    public init(onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    public func start(pid: pid_t) throws {
        do {
            try startTap(pid: pid)
        } catch {
            // Tap creation failing first surfaces as a TCC / audio-capture denial
            // (`AudioHardwareCreateProcessTap` returns non-`noErr` when the user
            // hasn't granted system-audio capture). Record the denial so the
            // readiness snapshot reflects it, then rethrow unchanged.
            AudioCaptureConsentStore.shared.record(.denied)
            throw error
        }
        AudioCaptureConsentStore.shared.record(.granted)
    }

    private func startTap(pid: pid_t) throws {
        let processObjectID = try processObjectID(for: pid)
        let tap = CATapDescription(stereoMixdownOfProcesses: [processObjectID])
        var id: AudioObjectID = 0
        let createStatus = AudioHardwareCreateProcessTap(tap, &id)
        guard createStatus == noErr else {
            throw NSError(domain: "CATap", code: Int(createStatus))
        }
        self.tapID = id

        var aggregate: AudioObjectID = 0
        do {
            let aggregateUID = "com.kacperpietrzyk.Nexus.meetings.tap.\(UUID().uuidString)"
            let aggregateDict: [String: Any] = [
                kAudioAggregateDeviceUIDKey: aggregateUID,
                kAudioAggregateDeviceIsPrivateKey: 1,
                kAudioAggregateDeviceIsStackedKey: 0,
                kAudioAggregateDeviceTapListKey: [
                    [kAudioSubTapUIDKey: try uid(of: id)]
                ],
            ]
            let aggStatus = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &aggregate)
            guard aggStatus == noErr else {
                throw NSError(domain: "CATapAggregate", code: Int(aggStatus))
            }
            self.aggregateID = aggregate
        } catch {
            if aggregate != 0 {
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            AudioHardwareDestroyProcessTap(id)
            aggregateID = 0
            tapID = 0
            throw error
        }

        do {
            let inputFormat = try Self.inputFormat(of: aggregateID)
            var procID: AudioDeviceIOProcID?
            let block: AudioDeviceIOBlock = { [onBuffer] _, inputData, _, _, _ in
                guard let buffer = CATapAudioBufferMapper.copy(inputData, format: inputFormat) else {
                    return
                }
                onBuffer(buffer)
            }
            let procStatus = AudioDeviceCreateIOProcIDWithBlock(
                &procID,
                aggregateID,
                ioQueue,
                block
            )
            guard procStatus == noErr, let procID else {
                throw NSError(domain: "CATapIOProc", code: Int(procStatus))
            }
            deviceProcID = procID

            let startStatus = AudioDeviceStart(aggregateID, procID)
            guard startStatus == noErr else {
                throw NSError(domain: "CATapDeviceStart", code: Int(startStatus))
            }
        } catch {
            stop()
            throw error
        }
    }

    public func stop() {
        if let proc = deviceProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
    }

    private func uid(of tapID: AudioObjectID) throws -> CFString {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uid: Unmanaged<CFString>?
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &uid)
        guard status == noErr else {
            throw NSError(domain: "CATapUID", code: Int(status))
        }
        guard let uid else {
            throw NSError(domain: "CATapUID", code: Int(kAudioHardwareBadObjectError))
        }
        return uid.takeUnretainedValue()
    }

    private func processObjectID(for pid: pid_t) throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var qualifierPID = pid
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            UInt32(MemoryLayout<pid_t>.size),
            &qualifierPID,
            &size,
            &processObjectID
        )
        guard status == noErr, processObjectID != kAudioObjectUnknown else {
            throw NSError(domain: "CATapProcessObject", code: Int(status))
        }
        return processObjectID
    }

    private static func inputFormat(of deviceID: AudioObjectID) throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &streamDescription)
        guard status == noErr else {
            throw NSError(domain: "CATapInputFormat", code: Int(status))
        }
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw NSError(domain: "CATapInputFormat", code: Int(kAudioHardwareUnsupportedOperationError))
        }
        return format
    }
}

enum CATapAudioBufferMapper {
    static func copy(_ inputData: UnsafePointer<AudioBufferList>, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let inputBuffers = UnsafeMutableAudioBufferListPointer(
            UnsafeMutablePointer(mutating: inputData)
        )
        guard let firstBuffer = inputBuffers.first, firstBuffer.mDataByteSize > 0 else {
            return nil
        }
        let bytesPerFrame = max(Int(format.streamDescription.pointee.mBytesPerFrame), 1)
        let frameLength = AVAudioFrameCount(Int(firstBuffer.mDataByteSize) / bytesPerFrame)
        guard frameLength > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength)
        else {
            return nil
        }
        buffer.frameLength = frameLength

        let outputBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        guard outputBuffers.count == inputBuffers.count else {
            return nil
        }

        for index in 0..<inputBuffers.count {
            let source = inputBuffers[index]
            var destination = outputBuffers[index]
            guard let sourceData = source.mData, let destinationData = destination.mData else {
                return nil
            }
            let byteCount = min(Int(source.mDataByteSize), Int(destination.mDataByteSize))
            destinationData.copyMemory(from: sourceData, byteCount: byteCount)
            destination.mDataByteSize = UInt32(byteCount)
            outputBuffers[index] = destination
        }

        return buffer
    }
}
#endif
