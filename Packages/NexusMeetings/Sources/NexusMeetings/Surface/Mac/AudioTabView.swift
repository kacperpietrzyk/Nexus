import AVFoundation
import NexusUI
import SwiftUI

public struct AudioTabView: View {
    private let meURL: URL
    private let othersURL: URL
    private let hasAudio: Bool

    @State private var mePlayer: AVAudioPlayer?
    @State private var othersPlayer: AVAudioPlayer?
    @State private var mePlaybackError: String?
    @State private var othersPlaybackError: String?
    @State private var playbackTick = 0

    private let playbackTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init(meURL: URL, othersURL: URL, hasAudio: Bool) {
        self.meURL = meURL
        self.othersURL = othersURL
        self.hasAudio = hasAudio
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio")
                .font(.title3.bold())

            if !hasAudio {
                ContentUnavailableView(
                    "Audio has been removed",
                    systemImage: "speaker.slash",
                    description: Text(
                        "Audio for this meeting was deleted per the retention policy. Transcript and summary are still available."
                    )
                )
            } else {
                playerRow(
                    title: "Me (mic)",
                    track: TrackPlayback(
                        player: $mePlayer,
                        other: $othersPlayer,
                        errorMessage: $mePlaybackError,
                        url: meURL
                    ),
                    tick: playbackTick
                )
                playerRow(
                    title: "Others (system)",
                    track: TrackPlayback(
                        player: $othersPlayer,
                        other: $mePlayer,
                        errorMessage: $othersPlaybackError,
                        url: othersURL
                    ),
                    tick: playbackTick
                )
            }

            Spacer()
        }
        .padding()
        .onDisappear {
            stopPlayback()
        }
        .onChange(of: hasAudio) { _, nextValue in
            guard !nextValue else { return }
            stopPlayback()
        }
        .onReceive(playbackTimer) { _ in
            guard hasAudio, mePlayer?.isPlaying == true || othersPlayer?.isPlaying == true else { return }
            playbackTick += 1
        }
    }

    /// Bundles the bindings + source URL for one audio track so `playerRow`
    /// stays within the parameter-count budget and `play` can stop the `other`
    /// track for exclusive playback.
    private struct TrackPlayback {
        let player: Binding<AVAudioPlayer?>
        let other: Binding<AVAudioPlayer?>
        let errorMessage: Binding<String?>
        let url: URL
    }

    private func playerRow(
        title: String,
        track: TrackPlayback,
        tick: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)

                Button {
                    play(track)
                } label: {
                    Image(systemName: track.player.wrappedValue?.isPlaying == true ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)

                if let currentPlayer = track.player.wrappedValue {
                    Text(
                        "\(format(time: currentPlayer.currentTime, tick: tick)) / \(format(time: currentPlayer.duration))"
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let error = track.errorMessage.wrappedValue {
                Text(error)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(NexusColor.Status.danger)
            }
        }
    }

    private func play(_ track: TrackPlayback) {
        let player = track.player
        let errorMessage = track.errorMessage
        let url = track.url
        errorMessage.wrappedValue = nil

        // Exclusive playback: interacting with one track stops the other so the
        // two recordings never play over each other.
        track.other.wrappedValue?.stop()
        track.other.wrappedValue = nil

        if let currentPlayer = player.wrappedValue, currentPlayer.url == url {
            if currentPlayer.isPlaying {
                currentPlayer.pause()
            } else {
                guard currentPlayer.play() else {
                    player.wrappedValue = nil
                    errorMessage.wrappedValue = "Playback failed to start."
                    return
                }
            }
            player.wrappedValue = currentPlayer
            return
        }

        do {
            player.wrappedValue?.stop()
            let nextPlayer = try AVAudioPlayer(contentsOf: url)
            nextPlayer.prepareToPlay()
            guard nextPlayer.play() else {
                player.wrappedValue = nil
                errorMessage.wrappedValue = "Playback failed to start."
                return
            }
            player.wrappedValue = nextPlayer
        } catch {
            player.wrappedValue = nil
            errorMessage.wrappedValue = "Playback failed: \(error.localizedDescription)"
        }
    }

    private func stopPlayback() {
        mePlayer?.stop()
        othersPlayer?.stop()
        mePlayer = nil
        othersPlayer = nil
        mePlaybackError = nil
        othersPlaybackError = nil
        playbackTick = 0
    }

    private func format(time: TimeInterval, tick: Int? = nil) -> String {
        _ = tick
        let totalSeconds = max(0, Int(time.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        guard hours > 0 else {
            return String(format: "%02d:%02d", minutes, seconds)
        }

        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
