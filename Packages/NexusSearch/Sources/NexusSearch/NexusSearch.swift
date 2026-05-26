import Foundation

/// NexusSearch — platform adapter for system search integrations (Spotlight today,
/// Quick Look + Siri suggestions in future phases). Depends only on NexusCore.
/// Mac + iOS only — CoreSpotlight is unavailable on watchOS.
public enum NexusSearch {
    public static let version = "0.1.0"
}
