import Foundation

@objc(MeetingHandlePayload)
public final class MeetingHandlePayload: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let meetingID: UUID
    public let folderPath: String

    public init(meetingID: UUID, folderPath: String) {
        self.meetingID = meetingID
        self.folderPath = folderPath
    }

    public init?(coder: NSCoder) {
        guard
            let uuidString = coder.decodeObject(of: NSString.self, forKey: "id") as String?,
            let folderPath = coder.decodeObject(of: NSString.self, forKey: "folder") as String?,
            let meetingID = UUID(uuidString: uuidString)
        else {
            return nil
        }

        self.meetingID = meetingID
        self.folderPath = folderPath
    }

    public func encode(with coder: NSCoder) {
        coder.encode(meetingID.uuidString as NSString, forKey: "id")
        coder.encode(folderPath as NSString, forKey: "folder")
    }
}
