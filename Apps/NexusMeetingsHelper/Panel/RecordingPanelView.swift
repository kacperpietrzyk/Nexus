import NexusMeetings
import SwiftUI

@MainActor
final class RecordingPanelState: ObservableObject {
    @Published var title: String
    @Published var elapsedSec: Int
    @Published var micLevel: Float
    @Published var othersLevel: Float

    init(title: String, elapsedSec: Int = 0, micLevel: Float = 0, othersLevel: Float = 0) {
        self.title = title
        self.elapsedSec = elapsedSec
        self.micLevel = micLevel
        self.othersLevel = othersLevel
    }

    func apply(_ snapshot: RecordingStateSnapshot) {
        elapsedSec = snapshot.elapsedSec
        micLevel = snapshot.micLevel
        othersLevel = snapshot.othersLevel
    }
}

struct RecordingPanelView: View {
    @ObservedObject var state: RecordingPanelState
    let onStop: () -> Void
    let onPause: () -> Void
    let onMinimize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                Text(formatTime(state.elapsedSec))
                    .font(.title3.monospacedDigit())
                Spacer(minLength: 12)
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
            }
            levelRow(title: "Mic", level: state.micLevel)
            levelRow(title: "Others", level: state.othersLevel)
            HStack {
                Button("Pause", action: onPause)
                Button(action: onStop) {
                    Text("Stop").bold()
                }
                Spacer()
                Button("Minimize", action: onMinimize)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private func levelRow(title: String, level: Float) -> some View {
        HStack {
            Text(title)
                .frame(width: 60, alignment: .leading)
            MeterBar(level: level)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let hours = clamped / 3_600
        let minutes = (clamped % 3_600) / 60
        let seconds = clamped % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

private struct MeterBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 4)
                    .fill(.tint)
                    .frame(width: fillWidth(proxy.size.width), height: 8)
            }
        }
        .frame(height: 8)
    }

    private func fillWidth(_ width: CGFloat) -> CGFloat {
        max(2, width * CGFloat(min(max(level, 0), 1)))
    }
}
