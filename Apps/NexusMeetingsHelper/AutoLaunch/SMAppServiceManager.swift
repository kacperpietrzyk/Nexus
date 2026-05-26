import Foundation
import ServiceManagement

enum SMAppServiceManager {
    private static let plistName = "com.kacperpietrzyk.nexus.meetings-helper.plist"

    static func register() throws {
        try service.register()
    }

    static func unregister() throws {
        try service.unregister()
    }

    static var status: SMAppService.Status {
        service.status
    }

    private static var service: SMAppService {
        SMAppService.agent(plistName: plistName)
    }
}
