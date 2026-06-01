import CoreText
import Foundation

/// Registers bundled OFL fonts (Inter + IBM Plex Mono) with the
/// process so SwiftUI's `Font.custom("Inter-Regular", size:)` and
/// `Font.custom("IBMPlexMono-Regular", size:)` resolve to our copies instead
/// of the system fallback. Call once at app startup, before any UI is
/// constructed.
///
/// Inter is bundled as a variable font (covers all weights via the `wght`
/// axis); the four weight-named TTF copies all point to the same variable
/// file so that `Font.custom` look-ups using any weight suffix succeed.
public enum NexusFontRegistration {

    static let fontFiles: [String] = [
        "Inter-Regular",
        "Inter-Medium",
        "Inter-SemiBold",
        "Inter-Bold",
        "IBMPlexMono-Regular",
        "IBMPlexMono-Medium",
        "IBMPlexMono-SemiBold",
        "IBMPlexMono-Bold",
    ]

    public static func registerAll() {
        debugLog("[NexusFontRegistration] starting; Bundle.module = \(Bundle.module.bundlePath)")
        var registered = 0
        var missing = 0
        var failed = 0
        for name in fontFiles {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                print("[NexusFontRegistration] MISSING resource: \(name).ttf")
                missing += 1
                continue
            }
            var error: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if ok {
                debugLog("[NexusFontRegistration] registered \(name)")
                registered += 1
            } else if let cfError = error?.takeRetainedValue() {
                let code = CFErrorGetCode(cfError)
                if code == 105 {
                    debugLog("[NexusFontRegistration] already registered \(name)")
                    registered += 1
                } else {
                    print("[NexusFontRegistration] FAILED \(name) code=\(code) err=\(cfError)")
                    failed += 1
                }
            } else {
                print("[NexusFontRegistration] FAILED \(name) (no error)")
                failed += 1
            }
        }
        let allFamilies = (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        let nexusFamilies = allFamilies.filter { name in
            let lower = name.lowercased()
            return lower.contains("inter") || lower.contains("plex")
        }
        debugLog(
            "[NexusFontRegistration] summary: \(registered)/\(fontFiles.count) registered, "
                + "\(missing) missing, \(failed) failed."
        )
        debugLog("[NexusFontRegistration] CoreText families matching: \(nexusFamilies)")
    }

    private static func debugLog(_ message: String) {
        if ProcessInfo.processInfo.environment["NEXUS_FONT_DEBUG"] == "1" {
            print(message)
        }
    }
}
