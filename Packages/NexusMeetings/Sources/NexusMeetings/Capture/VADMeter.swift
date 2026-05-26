import AVFoundation
import FluidAudio
import Foundation

public final class VADMeter: @unchecked Sendable {
    private let managerState = VADManagerState()
    private let managerLoader: @Sendable () async throws -> VadManager

    public init() {
        self.managerLoader = {
            try await VadManager()
        }
    }

    public func rmsLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard buffer.frameLength > 0 else { return 0 }

        switch buffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let channel = buffer.floatChannelData else { return 0 }
            return rmsLevel(channel[0], count: Int(buffer.frameLength)) { Double($0) }
        case .pcmFormatInt16:
            guard let channel = buffer.int16ChannelData else { return 0 }
            return rmsLevel(channel[0], count: Int(buffer.frameLength)) {
                Double($0) / Double(Int16.max)
            }
        case .pcmFormatInt32:
            guard let channel = buffer.int32ChannelData else { return 0 }
            return rmsLevel(channel[0], count: Int(buffer.frameLength)) {
                Double($0) / Double(Int32.max)
            }
        case .pcmFormatFloat64, .otherFormat:
            return 0
        @unknown default:
            return 0
        }
    }

    private func rmsLevel<T>(
        _ samples: UnsafeMutablePointer<T>,
        count: Int,
        normalize: (T) -> Double
    ) -> Float {
        guard count > 0 else { return 0 }
        var sum: Double = 0
        for index in 0..<count {
            let sample = normalize(samples[index])
            sum += sample * sample
        }
        let rms = sqrt(sum / Double(count))
        return Float(min(max(rms, 0), 1))
    }

    public func isSpeechActive(_ buffer: AVAudioPCMBuffer) async -> Bool {
        do {
            guard let samples = samples(from: buffer) else { return rmsFallback(buffer) }
            let manager = try await managerState.manager(loader: managerLoader)
            let results = try await manager.process(samples)
            guard !results.isEmpty else { return rmsFallback(buffer) }
            return results.contains { $0.isVoiceActive }
        } catch {
            return rmsFallback(buffer)
        }
    }

    private func rmsFallback(_ buffer: AVAudioPCMBuffer) -> Bool {
        rmsLevel(buffer) > 0.02
    }

    private func samples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        guard buffer.frameLength > 0 else { return nil }

        let count = Int(buffer.frameLength)
        switch buffer.format.commonFormat {
        case .pcmFormatInt16:
            guard let channel = buffer.int16ChannelData else { return nil }
            return (0..<count).map { index in
                Float(channel[0][index]) / Float(Int16.max)
            }
        case .pcmFormatFloat32:
            guard let channel = buffer.floatChannelData else { return nil }
            return (0..<count).map { index in
                channel[0][index]
            }
        case .pcmFormatFloat64, .pcmFormatInt32, .otherFormat:
            return nil
        @unknown default:
            return nil
        }
    }
}

private final class VADManagerState: @unchecked Sendable {
    private let lock = NSLock()
    private var loadID = 0
    private var loadTask: (id: Int, task: Task<VadManager, any Error>)?

    func manager(loader: @escaping @Sendable () async throws -> VadManager) async throws -> VadManager {
        let load = task(loader: loader)
        do {
            return try await load.task.value
        } catch {
            clearFailedTask(id: load.id)
            throw error
        }
    }

    private func task(
        loader: @escaping @Sendable () async throws -> VadManager
    ) -> (id: Int, task: Task<VadManager, any Error>) {
        lock.lock()
        defer { lock.unlock() }

        if let loadTask {
            return loadTask
        }

        loadID += 1
        let loadTask = (
            id: loadID,
            task: Task<VadManager, any Error> {
                try await loader()
            }
        )
        self.loadTask = loadTask
        return loadTask
    }

    private func clearFailedTask(id: Int) {
        lock.lock()
        defer { lock.unlock() }

        if loadTask?.id == id {
            loadTask = nil
        }
    }
}
