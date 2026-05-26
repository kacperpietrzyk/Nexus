import InboxShell
import SwiftUI

extension TodayDashboard {
    func markInboxRead() {
        NotificationCenter.default.post(name: .nexusMarkInboxRead, object: nil)
    }

    nonisolated static func selectionAfterOpeningAsk() -> TodayNavSelection { .agent }

    nonisolated static func canOpenAgent(selectionProvided: Bool, callbackProvided: Bool) -> Bool {
        selectionProvided || callbackProvided
    }

    var canOpenAgent: Bool {
        Self.canOpenAgent(selectionProvided: selection != nil, callbackProvided: onOpenAgent != nil)
    }

    func openAsk() {
        if let onOpenAgent {
            onOpenAgent()
        } else {
            activeSelection.wrappedValue = Self.selectionAfterOpeningAsk()
        }
    }

    func openTaskCapture() {
        onOpenCapture(.task)
    }
}
