import Foundation

public struct RecordingLevels: Equatable, Sendable {
    public let micLevel: Float
    public let othersLevel: Float

    public init(micLevel: Float, othersLevel: Float) {
        self.micLevel = micLevel
        self.othersLevel = othersLevel
    }

    public static let zero = RecordingLevels(micLevel: 0, othersLevel: 0)
}

final class AudioLevelStore: @unchecked Sendable {
    private let lock = NSLock()
    private var micLevel: Float = 0
    private var othersLevel: Float = 0

    func reset() {
        lock.lock()
        micLevel = 0
        othersLevel = 0
        lock.unlock()
    }

    func updateMic(_ level: Float) {
        lock.lock()
        micLevel = Self.clamp(level)
        lock.unlock()
    }

    func updateOthers(_ level: Float) {
        lock.lock()
        othersLevel = Self.clamp(level)
        lock.unlock()
    }

    func snapshot() -> RecordingLevels {
        lock.lock()
        defer { lock.unlock() }
        return RecordingLevels(micLevel: micLevel, othersLevel: othersLevel)
    }

    private static func clamp(_ level: Float) -> Float {
        min(max(level, 0), 1)
    }
}
