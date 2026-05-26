import Foundation

/// User's network preference for a request. Default is `.offlineOnly` (D5 — privacy-first).
/// Cloud calls are allowed only when this is `.cloudAllowed` AND consent + quota check pass.
public enum ConnectivityPreference: String, Codable, Sendable, CaseIterable {
    case offlineOnly
    case cloudAllowed
}
