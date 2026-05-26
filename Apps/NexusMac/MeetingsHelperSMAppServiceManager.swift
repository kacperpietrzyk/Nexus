import Foundation
import ServiceManagement
import os

enum MeetingsHelperSMAppServiceManager {
    private static let plistName = "com.kacperpietrzyk.nexus.meetings-helper.plist"
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus.Mac",
        category: "MeetingsHelperSMAppServiceManager"
    )

    static func registerIfNeeded() {
        let service = SMAppService.agent(plistName: plistName)
        switch service.status {
        case .notRegistered:
            do {
                try service.register()
                logger.info("Registered meetings helper with SMAppService")
            } catch {
                logger.error(
                    "Meetings helper registration failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        case .requiresApproval:
            logger.info("Meetings helper requires user approval in Login Items")
        case .enabled:
            return
        default:
            logger.info("Meetings helper SMAppService status: \(String(describing: service.status), privacy: .public)")
        }
    }
}
