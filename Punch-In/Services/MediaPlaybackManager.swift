import AVFoundation
import Combine
import Foundation

@MainActor
final class MediaPlaybackManager: ObservableObject {
    @Published private(set) var currentItem: ProfileMediaItem?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private let firestoreService: any FirestoreService
    private let player: AVPlayer
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var hasRecordedPlayForCurrentItem = false
    private var cancellables = Set<AnyCancellable>()

    init(firestoreService: any FirestoreService = MockFirestoreService()) {
        self.firestoreService = firestoreService
        player = AVPlayer()
        configureAudioSession()
        attachObservers()
        observePlaybackState()
    }

    func play(media: ProfileMediaItem) {
        prepare(media: media)
        guard player.currentItem != nil else { return }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if let item = currentItem {
            play(media: item)
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        currentItem = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
        hasRecordedPlayForCurrentItem = false
    }

    func prepare(media: ProfileMediaItem) {
        guard let url = media.mediaURL else { return }

        let needsNewItem: Bool = {
            guard let currentItem else { return true }
            if currentItem.id != media.id { return true }
            return currentItem.mediaURL != media.mediaURL
        }()

        if needsNewItem {
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            observeDuration(for: item)
            duration = 0
            currentTime = 0
            progress = 0
            hasRecordedPlayForCurrentItem = false
        }

        currentItem = media
    }

    var avPlayer: AVPlayer {
        player
    }

    func updateMetadata(with item: ProfileMediaItem) {
        guard currentItem?.id == item.id else { return }
        currentItem = item
    }

    func seek(to fraction: Double) {
        guard let currentItem else { return }
        guard fraction.isFinite else { return }

        let clamped = min(max(fraction, 0), 1)
        let targetSeconds = duration * clamped
        let time = CMTime(seconds: targetSeconds, preferredTimescale: 600)
        player.seek(to: time) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.currentTime = targetSeconds
                self.progress = clamped
                if targetSeconds <= 1 {
                    self.hasRecordedPlayForCurrentItem = false
                }
            }
        }
    }

    func isPlaying(media: ProfileMediaItem) -> Bool {
        currentItem?.id == media.id && isPlaying
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            Logger.log("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    private func attachObservers() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let seconds = time.seconds
                if seconds.isFinite {
                    self.currentTime = seconds
                }
                if self.duration > 0 {
                    self.progress = min(max(self.currentTime / self.duration, 0), 1)
                } else {
                    self.progress = 0
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.player.seek(to: .zero)
                self.isPlaying = false
                self.progress = 0
                self.currentTime = 0
                self.hasRecordedPlayForCurrentItem = false
            }
        }
    }

    private func observePlaybackState() {
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isPlaying = status == .playing
                if status == .playing, let item = self.currentItem {
                    self.recordPlay(for: item)
                }
            }
            .store(in: &cancellables)
    }

    private func observeDuration(for item: AVPlayerItem) {
        Task.detached { [weak self] in
            guard let duration = try? await item.asset.load(.duration) else { return }
            guard let self else { return }
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite else { return }
            await MainActor.run {
                self.duration = seconds
            }
        }
    }

    private func recordPlay(for media: ProfileMediaItem) {
        guard hasRecordedPlayForCurrentItem == false else { return }
        hasRecordedPlayForCurrentItem = true

        Task { [weak self] in
            guard let self else { return }
            do {
                try await firestoreService.incrementMediaPlayCount(ownerId: media.ownerId, mediaId: media.id)
                await MainActor.run {
                    if var current = self.currentItem, current.id == media.id {
                        current.playCount += 1
                        self.currentItem = current
                    }
                }
            } catch {
                await MainActor.run {
                    self.hasRecordedPlayForCurrentItem = false
                    Logger.log("Failed to increment play count for media \(media.id): \(error.localizedDescription)")
                }
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        cancellables.removeAll()
    }
}
