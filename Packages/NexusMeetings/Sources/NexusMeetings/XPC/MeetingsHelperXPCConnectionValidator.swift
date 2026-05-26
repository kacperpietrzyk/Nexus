import Foundation

#if os(macOS)
import Security
#endif

public struct MeetingsHelperXPCSigningInfo: Equatable, Sendable {
    public let teamIdentifier: String?
    public let bundleIdentifier: String?

    public init(teamIdentifier: String?, bundleIdentifier: String?) {
        self.teamIdentifier = teamIdentifier
        self.bundleIdentifier = bundleIdentifier
    }
}

public struct MeetingsHelperXPCConnectionValidator: Sendable {
    public enum Verdict: Equatable, Sendable {
        case accepted
        case rejected
    }

    public static let nexusTeamIdentifier = "UDZLCK86PY"
    public static let allowedBundleIdentifiers: Set<String> = [
        "com.kacperpietrzyk.Nexus.Mac",
        "com.kacperpietrzyk.nexus.meetings-helper",
    ]

    private let allowUnsignedDebugConnections: Bool

    public init(
        allowUnsignedDebugConnections: Bool = ProcessInfo.processInfo
            .environment["NEXUS_MEETINGS_HELPER_ALLOW_UNSIGNED_XPC"] == "1"
    ) {
        self.allowUnsignedDebugConnections = allowUnsignedDebugConnections
    }

    public func validate(signingInfo: MeetingsHelperXPCSigningInfo?) -> Verdict {
        guard
            let signingInfo,
            signingInfo.teamIdentifier == Self.nexusTeamIdentifier,
            let bundleIdentifier = signingInfo.bundleIdentifier,
            Self.allowedBundleIdentifiers.contains(bundleIdentifier)
        else {
            return .rejected
        }
        return .accepted
    }

    #if os(macOS)
    public func validate(processIdentifier: pid_t) -> Verdict {
        guard let signingInfo = Self.signingInfo(forProcessIdentifier: processIdentifier) else {
            #if DEBUG
            // Local unsigned helper runs can opt in explicitly via environment.
            // Production and default debug runs fail closed when SecCode cannot
            // identify the connecting process.
            return allowUnsignedDebugConnections ? .accepted : .rejected
            #else
            return .rejected
            #endif
        }
        return validate(signingInfo: signingInfo)
    }

    static func signingInfo(forProcessIdentifier processIdentifier: pid_t) -> MeetingsHelperXPCSigningInfo? {
        let attributes = [kSecGuestAttributePid as String: processIdentifier] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
            return nil
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }

        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess,
            let dictionary = info as? [String: Any]
        else {
            return nil
        }

        let bundleIdentifier = dictionary[kSecCodeInfoIdentifier as String] as? String
        let teamIdentifier =
            dictionary[kSecCodeInfoTeamIdentifier as String] as? String
            ?? Self.teamIdentifierFromEntitlements(dictionary)

        return MeetingsHelperXPCSigningInfo(
            teamIdentifier: teamIdentifier,
            bundleIdentifier: bundleIdentifier
        )
    }

    private static func teamIdentifierFromEntitlements(_ dictionary: [String: Any]) -> String? {
        guard
            let entitlements = dictionary[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
            let applicationIdentifier = entitlements["com.apple.application-identifier"] as? String,
            let separator = applicationIdentifier.firstIndex(of: ".")
        else {
            return nil
        }
        return String(applicationIdentifier[..<separator])
    }
    #else
    public func validate(processIdentifier: pid_t) -> Verdict {
        allowUnsignedDebugConnections ? .accepted : .rejected
    }
    #endif
}
