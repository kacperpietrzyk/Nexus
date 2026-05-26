import Foundation

@objc public protocol MeetingsHelperXPCProtocol {
    func startRecording(
        detectionSource: String,
        appBundleID: String?,
        suggestedTitle: String?,
        pid: Int32,
        reply: @escaping (MeetingHandlePayload?, Error?) -> Void
    )

    func startRecordingWithPicker(reply: @escaping (MeetingHandlePayload?, Error?) -> Void)
    func stopRecording(meetingID: NSString, reply: @escaping (Error?) -> Void)
    func pauseRecording(meetingID: NSString, reply: @escaping (Error?) -> Void)
    func resumeRecording(meetingID: NSString, reply: @escaping (Error?) -> Void)
    func currentRecordingState(reply: @escaping (RecordingStateSnapshot) -> Void)
    func reprocess(meetingID: NSString, fromStage: NSString, reply: @escaping (Error?) -> Void)
    func cancelProcessing(meetingID: NSString, reply: @escaping (Error?) -> Void)
}
