/// Per-request provider hint. `.auto` is the default and currently the only
/// supported mode after the MLX-first local-provider pivot.
public enum ProviderPreference: String, Codable, Sendable, CaseIterable {
    case auto
}
