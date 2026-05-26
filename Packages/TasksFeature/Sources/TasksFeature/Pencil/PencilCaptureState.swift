#if os(iOS)
import Foundation
import Observation

@MainActor
@Observable
public final class PencilCaptureState {
    public var text = ""
    public var isRecognizing = false
    public var error: String?

    private let recognize: @MainActor () async throws -> String

    public init(recognize: @escaping @MainActor () async throws -> String) {
        self.recognize = recognize
    }

    public func recognizeDrawing() async {
        isRecognizing = true
        defer { isRecognizing = false }
        do {
            text = try await recognize()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}
#endif
