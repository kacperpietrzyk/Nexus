import Foundation
import Observation

@MainActor
@Observable
public final class FocusModeState {
    public private(set) var isInFocus: Bool = false
    public private(set) var pinnedTaskID: UUID?
    public private(set) var emptyHintTrigger: Int = 0

    public init() {}

    public func enter(taskID: UUID) {
        pinnedTaskID = taskID
        isInFocus = true
    }

    public func exit() {
        pinnedTaskID = nil
        isInFocus = false
    }

    public func toggle(pickFrom: () -> UUID?) {
        if isInFocus {
            exit()
            return
        }
        if let candidate = pickFrom() {
            enter(taskID: candidate)
        } else {
            emptyHintTrigger &+= 1
        }
    }
}
