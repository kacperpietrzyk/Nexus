import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

public struct ContentSharingPickerResult: Sendable {
    public let bundleID: String
    public let pid: pid_t
    public let displayName: String

    public init(bundleID: String, pid: pid_t, displayName: String) {
        self.bundleID = bundleID
        self.pid = pid
        self.displayName = displayName
    }
}

public protocol ContentSharingPickerPresenting: Sendable {
    func present() async throws -> ContentSharingPickerResult
}

public enum ContentSharingPickerError: Error, Sendable {
    case presentationAlreadyActive
}

#if canImport(ScreenCaptureKit)
public final class ContentSharingPickerCapture: ContentSharingPickerPresenting, @unchecked Sendable {
    private let presentationState = PickerPresentationState()

    public init() {}

    public func present() async throws -> ContentSharingPickerResult {
        let request = PickerPresentationRequest(state: presentationState)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.start(continuation: continuation)
            }
        } onCancel: {
            request.cancel()
        }
    }

    private final class PickerObserver: NSObject, SCContentSharingPickerObserver, @unchecked Sendable {
        private let lock = NSLock()
        private var didResume = false
        private let continuation: CheckedContinuation<ContentSharingPickerResult, any Error>
        private weak var request: PickerPresentationRequest?

        init(
            continuation: CheckedContinuation<ContentSharingPickerResult, any Error>,
            request: PickerPresentationRequest
        ) {
            self.continuation = continuation
            self.request = request
        }

        func cancel() {
            resume(SCContentSharingPicker.shared, with: .failure(CancellationError()))
        }

        func contentSharingPicker(
            _ picker: SCContentSharingPicker,
            didCancelFor stream: SCStream?
        ) {
            resume(picker, with: .failure(CancellationError()))
        }

        func contentSharingPicker(
            _ picker: SCContentSharingPicker,
            didUpdateWith filter: SCContentFilter,
            for stream: SCStream?
        ) {
            guard let app = filter.includedApplications.first else {
                resume(picker, with: .failure(CancellationError()))
                return
            }

            resume(
                picker,
                with: .success(
                    ContentSharingPickerResult(
                        bundleID: app.bundleIdentifier,
                        pid: app.processID,
                        displayName: app.applicationName
                    )
                )
            )
        }

        func contentSharingPickerStartDidFailWithError(_ error: any Error) {
            resume(SCContentSharingPicker.shared, with: .failure(error))
        }

        private func resume(
            _ picker: SCContentSharingPicker,
            with result: Result<ContentSharingPickerResult, any Error>
        ) {
            lock.lock()
            guard !didResume else {
                lock.unlock()
                return
            }
            didResume = true
            lock.unlock()

            request?.finish(self, picker: picker)

            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }

    private final class PickerPresentationRequest: @unchecked Sendable {
        private let condition = NSCondition()
        private let state: PickerPresentationState
        private var didCancel = false
        private var isPresenting = false
        private var observer: PickerObserver?

        init(state: PickerPresentationState) {
            self.state = state
        }

        func start(continuation: CheckedContinuation<ContentSharingPickerResult, any Error>) {
            condition.lock()
            if didCancel {
                condition.unlock()
                continuation.resume(throwing: CancellationError())
                return
            }
            condition.unlock()

            let observer = PickerObserver(continuation: continuation, request: self)
            do {
                try state.begin(observer)
            } catch {
                continuation.resume(throwing: error)
                return
            }

            condition.lock()
            if didCancel {
                condition.unlock()
                observer.cancel()
                return
            }
            self.observer = observer
            isPresenting = true
            condition.unlock()

            state.present()

            condition.lock()
            isPresenting = false
            condition.broadcast()
            condition.unlock()
        }

        func cancel() {
            condition.lock()
            didCancel = true
            while isPresenting {
                condition.wait()
            }
            let observer = observer
            condition.unlock()

            observer?.cancel()
        }

        func finish(_ observer: PickerObserver, picker: SCContentSharingPicker) {
            state.finish(observer, picker: picker)

            condition.lock()
            if self.observer === observer {
                self.observer = nil
            }
            condition.unlock()
        }
    }

    private final class PickerPresentationState: @unchecked Sendable {
        private let lock = NSLock()
        private var activeObserver: PickerObserver?

        func begin(_ observer: PickerObserver) throws {
            lock.lock()
            defer { lock.unlock() }

            guard activeObserver == nil else {
                throw ContentSharingPickerError.presentationAlreadyActive
            }

            activeObserver = observer
            configurePicker(SCContentSharingPicker.shared)
            SCContentSharingPicker.shared.add(observer)
        }

        func present() {
            SCContentSharingPicker.shared.isActive = true
            SCContentSharingPicker.shared.present()
        }

        func finish(_ observer: PickerObserver, picker: SCContentSharingPicker) {
            picker.remove(observer)

            lock.lock()
            if activeObserver === observer {
                activeObserver = nil
            }
            lock.unlock()
        }

        private func configurePicker(_ picker: SCContentSharingPicker) {
            var configuration = picker.defaultConfiguration
            configuration.allowedPickerModes = [.singleWindow, .singleApplication]
            picker.defaultConfiguration = configuration
        }
    }
}
#endif
