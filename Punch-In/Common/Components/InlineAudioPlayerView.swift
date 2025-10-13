import AVFoundation
import SwiftUI

struct InlineAudioPlayerView: View {
    @StateObject private var model: AudioPlayerModel

    init(url: URL) {
        _model = StateObject(wrappedValue: AudioPlayerModel(url: url))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.primaryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                Text(model.timeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            model.stop()
        }
    }
}

@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0

    private let player: AVPlayer
    private var timeObserver: Any?
    private var playToEndObserver: NSObjectProtocol?

    var timeLabel: String {
        guard duration > 0 else { return "00:00" }
        let elapsed = formatTime(currentTime)
        let total = formatTime(duration)
        return "\(elapsed) / \(total)"
    }

    init(url: URL) {
        player = AVPlayer(url: url)
        setupObservers()
    }

    private func setupObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                    self.progress = min(max(self.currentTime / itemDuration, 0), 1)
                }
            }
        }

        playToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.player.seek(to: .zero)
                self.isPlaying = false
                self.progress = 0
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func stop() {
        player.pause()
        player.seek(to: .zero)
        isPlaying = false
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let playToEndObserver {
            NotificationCenter.default.removeObserver(playToEndObserver)
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
