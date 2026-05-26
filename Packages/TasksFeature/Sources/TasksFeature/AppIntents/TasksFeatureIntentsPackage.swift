#if canImport(AppIntents)
import AppIntents

/// Marker required for SPM-based AppIntents discovery. Do not delete even if it
/// looks unused — without this conformance the framework's metadata extractor
/// can miss intents declared inside Swift packages.
public struct TasksFeatureIntentsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] { [] }
    public init() {}
}
#endif
