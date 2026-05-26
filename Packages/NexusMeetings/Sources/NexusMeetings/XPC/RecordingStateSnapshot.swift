import Foundation

@objc(RecordingStateSnapshot)
public final class RecordingStateSnapshot: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let isRecording: Bool
    public let meetingID: UUID?
    public let elapsedSec: Int
    public let micLevel: Float
    public let othersLevel: Float

    public init(
        isRecording: Bool,
        meetingID: UUID?,
        elapsedSec: Int,
        micLevel: Float,
        othersLevel: Float
    ) {
        self.isRecording = isRecording
        self.meetingID = meetingID
        self.elapsedSec = elapsedSec
        self.micLevel = micLevel
        self.othersLevel = othersLevel
    }

    public init?(coder: NSCoder) {
        isRecording = coder.decodeBool(forKey: "rec")
        if let uuidString = coder.decodeObject(of: NSString.self, forKey: "id") as String? {
            meetingID = UUID(uuidString: uuidString)
        } else {
            meetingID = nil
        }
        elapsedSec = coder.decodeInteger(forKey: "elapsed")
        micLevel = coder.decodeFloat(forKey: "mic")
        othersLevel = coder.decodeFloat(forKey: "others")
    }

    public func encode(with coder: NSCoder) {
        coder.encode(isRecording, forKey: "rec")
        coder.encode(meetingID?.uuidString as NSString?, forKey: "id")
        coder.encode(elapsedSec, forKey: "elapsed")
        coder.encode(micLevel, forKey: "mic")
        coder.encode(othersLevel, forKey: "others")
    }
}
