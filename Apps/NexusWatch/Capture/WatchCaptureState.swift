import Foundation
import Observation

@MainActor
@Observable
final class WatchCaptureState {
    enum Phase: Equatable {
        case idle
        case sending
        case sent
        case error(String)
    }

    var input = ""
    private(set) var phase: Phase = .idle

    private let bridge: WatchPhoneBridge

    init(bridge: WatchPhoneBridge = .shared) {
        self.bridge = bridge
    }

    func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .sending
        do {
            try await bridge.sendCapture(input: trimmed)
            phase = .sent
            input = ""
        } catch {
            phase = .error(error.localizedDescription)
        }
    }
}
