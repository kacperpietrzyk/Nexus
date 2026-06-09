import FluidAudio
import Foundation

/// Builds the default in-process readiness computer (live permission, directory
/// model, and environment probes) so the **main app** and the helper produce
/// identical snapshots from the same on-disk model caches. Previously this wiring
/// lived only inside the helper, which left the main app unable to compute
/// readiness itself.
public enum MeetingsReadinessFactory {
    /// Directory resolvers pointing at the same caches the processing pipeline
    /// reads, so a "ready" row means the providers can actually load the model.
    public static func defaultModelResolvers() -> [DirectoryModelProbe.Resolver] {
        [
            DirectoryModelProbe.Resolver(id: .parakeet) {
                AsrModels.defaultCacheDirectory(for: .v3)
            },
            DirectoryModelProbe.Resolver(id: .sortformer) {
                MLModelConfigurationUtils.defaultModelsDirectory(for: .sortformer)
            },
            DirectoryModelProbe.Resolver(id: .whisperKit) {
                WhisperKitMeetingProvider.defaultLocalModelFolder()
            },
        ]
    }

    public static func makeComputer(
        clock: @escaping @Sendable () -> Date = { Date() }
    ) -> MeetingsReadinessComputer {
        MeetingsReadinessComputer(
            permissions: LivePermissionProbe(),
            models: DirectoryModelProbe(resolvers: defaultModelResolvers()),
            environment: LiveEnvironmentProbe(),
            clock: clock
        )
    }
}
