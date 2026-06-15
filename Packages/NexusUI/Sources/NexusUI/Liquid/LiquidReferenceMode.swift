import Foundation

/// Debug-only switch for visual QA fixtures used to compare Liquid screens
/// against `liquid_productivity_design_system/references`.
public enum LiquidReferenceMode {
    public static let environmentKey = "NEXUS_LIQUID_REFERENCE_DATA"
    public static let launchArgument = "--liquid-reference-data"

    public static var isEnabled: Bool {
        isEnabled(
            environment: ProcessInfo.processInfo.environment,
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    public static func isEnabled(
        environment: [String: String],
        arguments: [String] = []
    ) -> Bool {
        #if DEBUG
        if arguments.contains(launchArgument) {
            return true
        }
        guard
            let raw = environment[environmentKey]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        else {
            return false
        }
        return raw == "1" || raw == "true" || raw == "yes"
        #else
        return false
        #endif
    }
}
