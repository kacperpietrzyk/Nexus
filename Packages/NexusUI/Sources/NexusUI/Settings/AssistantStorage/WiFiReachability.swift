import Network
import Observation

/// Observable Wi-Fi reachability for gating large model downloads to Wi-Fi.
@MainActor @Observable
public final class WiFiReachability {
    public private(set) var isOnWiFi: Bool = false
    private let monitor = NWPathMonitor()

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let onWiFi = path.status == .satisfied && !path.isExpensive
            Task { @MainActor in self?.isOnWiFi = onWiFi }
        }
        monitor.start(queue: DispatchQueue(label: "nexus.wifi.reachability"))
    }

    deinit { monitor.cancel() }
}
