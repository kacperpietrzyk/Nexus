import Foundation

/// User's cost preference. Currently advisory — `AIRouter` does not yet use it
/// for selection, but persists it on `AIResponse` so usage logs reflect intent.
public enum CostPreference: String, Codable, Sendable, CaseIterable {
    case free
    case anyPaid
}
