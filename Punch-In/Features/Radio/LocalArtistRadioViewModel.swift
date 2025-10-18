import Combine
import Foundation

@MainActor
final class LocalArtistRadioViewModel: ObservableObject {
    struct RadioTrack: Identifiable {
        let media: ProfileMediaItem
        let owner: UserProfile?

        var id: String {
            "\(media.ownerId)|\(media.id)"
        }

        var displayTitle: String {
            media.title.isEmpty ? media.category.displayTitle : media.title
        }

        var ownerDisplayName: String {
            owner?.displayName.isEmpty == false ? (owner?.displayName ?? "") : (owner?.username ?? "Unknown Artist")
        }

        var genreDisplayName: String? {
            media.primaryGenre?.displayName
        }

        var originStateDisplayName: String? {
            media.originState?.displayName
        }
    }

    @Published private(set) var lineup: [RadioTrack] = []
    @Published private(set) var nowPlaying: RadioTrack?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var likeErrorMessage: String?
    @Published private(set) var isProcessingLike = false
    @Published private(set) var currentQueueIndex: Int?
    @Published private(set) var filter = RadioFeedFilter()
    @Published var isShuffleEnabled = false
    @Published var isRepeatEnabled = false

    var canLikeTracks: Bool {
        currentUserProvider() != nil
    }

    private let firestoreService: any FirestoreService
    private let playbackManager: MediaPlaybackManager
    private let currentUserProvider: () -> UserProfile?
    private var cancellables = Set<AnyCancellable>()
    private var ownerProfiles: [String: UserProfile] = [:]
    private var likedRecords: [String: RadioLike] = [:]
    private var trackLookup: [String: RadioTrack] = [:]
    private var hasLoadedOnce = false

    init(
        firestoreService: any FirestoreService,
        playbackManager: MediaPlaybackManager,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.firestoreService = firestoreService
        self.playbackManager = playbackManager
        self.currentUserProvider = currentUserProvider

        playbackManager.$playbackCompletionCount
            .dropFirst()
            .sink { [weak self] _ in
                self?.handleTrackCompletion()
            }
            .store(in: &cancellables)

        playbackManager.$currentItem
            .sink { [weak self] item in
                self?.syncWithCurrentPlayback(currentItem: item)
            }
            .store(in: &cancellables)
    }

    func loadIfNeeded() async {
        if hasLoadedOnce {
            await refreshLineup()
        } else {
            hasLoadedOnce = true
            await refreshLineup()
        }
    }

    func refreshLineup() async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let currentUserId = currentUserProvider()?.id
            let items = try await firestoreService.fetchRadioEligibleMedia(
                limit: 64,
                genre: filter.genre,
                state: filter.region.state
            )
            let likes: [RadioLike]
            if let currentUserId {
                likes = try await firestoreService.fetchRadioLikes(for: currentUserId)
            } else {
                likes = []
            }

            var ownerIDs = Set(items.map(\.ownerId))
            ownerIDs.formUnion(likes.map(\.ownerId))

            if ownerIDs.isEmpty == false {
                let profiles = try await firestoreService.fetchUserProfiles(for: Array(ownerIDs))
                ownerProfiles = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            } else {
                ownerProfiles = [:]
            }

            trackLookup = [:]
            lineup = items.map { media in
                let track = RadioTrack(media: media, owner: ownerProfiles[media.ownerId])
                trackLookup[self.key(forOwner: media.ownerId, mediaId: media.id)] = track
                return track
            }

            await populateLikedTracks(from: likes)
            syncWithCurrentPlayback(currentItem: playbackManager.currentItem, preferFirstItem: true)

            if playbackManager.currentItem == nil, let first = lineup.first {
                play(track: first)
            }

            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func updateGenre(_ genre: MusicGenre?) {
        filter.genre = genre
        Task { await refreshLineup() }
    }

    func updateRegion(_ region: RadioRegion) {
        filter.region = region
        Task { await refreshLineup() }
    }

    func play(track: RadioTrack) {
        trackLookup[key(forOwner: track.media.ownerId, mediaId: track.media.id)] = track
        playbackManager.play(media: track.media)
        nowPlaying = track
        if let index = lineup.firstIndex(where: { $0.id == track.id }) {
            currentQueueIndex = index
        } else {
            currentQueueIndex = nil
        }
    }

    func play(at index: Int) {
        guard lineup.indices.contains(index) else { return }
        play(track: lineup[index])
    }

    func playNext() {
        guard lineup.isEmpty == false else { return }

        if isShuffleEnabled {
            playRandomTrack()
            return
        }

        if let index = currentQueueIndex {
            let nextIndex = (index + 1) % lineup.count
            play(at: nextIndex)
        } else {
            play(at: 0)
        }
    }

    func playPrevious() {
        guard lineup.isEmpty == false else { return }

        if playbackManager.currentTime > 3, let track = nowPlaying {
            play(track: track)
            return
        }

        if let index = currentQueueIndex {
            let previousIndex = (index - 1 + lineup.count) % lineup.count
            play(at: previousIndex)
        } else {
            play(at: max(lineup.count - 1, 0))
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
        if isShuffleEnabled {
            playRandomTrack()
        }
    }

    func toggleRepeat() {
        isRepeatEnabled.toggle()
        if isRepeatEnabled {
            replayCurrent()
        }
    }

    private func playRandomTrack() {
        guard lineup.isEmpty == false else { return }

        if lineup.count == 1 {
            replayCurrent()
            return
        }

        let currentIndex = currentQueueIndex
        var indices = Array(lineup.indices)
        if let currentIndex, indices.count > 1 {
            indices.removeAll { $0 == currentIndex }
        }

        if let randomIndex = indices.randomElement() {
            play(at: randomIndex)
        } else {
            play(at: Int.random(in: 0..<lineup.count))
        }
    }

    func replayCurrent() {
        guard let current = nowPlaying else { return }
        playbackManager.play(media: current.media)
        playbackManager.seek(to: 0)
    }

    func toggleLike(for track: RadioTrack) async {
        guard let currentUserId = currentUserProvider()?.id else {
            likeErrorMessage = "Sign in to save tracks you love."
            return
        }

        let key = key(forOwner: track.media.ownerId, mediaId: track.media.id)
        let isLiked = likedRecords[key] != nil

        isProcessingLike = true
        defer { isProcessingLike = false }

        do {
            if isLiked {
                try await firestoreService.unlikeRadioTrack(
                    ownerId: track.media.ownerId,
                    mediaId: track.media.id,
                    userId: currentUserId
                )
                likedRecords.removeValue(forKey: key)
            } else {
                try await firestoreService.likeRadioTrack(
                    ownerId: track.media.ownerId,
                    mediaId: track.media.id,
                    userId: currentUserId
                )
                let record = RadioLike(
                    ownerId: track.media.ownerId,
                    mediaId: track.media.id,
                    userId: currentUserId,
                    createdAt: Date()
                )
                likedRecords[key] = record
            }

            likeErrorMessage = nil
        } catch {
            likeErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func isLiked(_ track: RadioTrack) -> Bool {
        likedRecords[key(forOwner: track.media.ownerId, mediaId: track.media.id)] != nil
    }

    var likedTracks: [RadioTrack] {
        lineup.filter { isLiked($0) }
    }

    private func populateLikedTracks(from likes: [RadioLike]) async {
        likedRecords = Dictionary(uniqueKeysWithValues: likes.map { (key(forOwner: $0.ownerId, mediaId: $0.mediaId), $0) })
    }

    private func handleTrackCompletion() {
        guard lineup.isEmpty == false else { return }
        if isRepeatEnabled {
            replayCurrent()
            return
        }
        playNext()
    }

    private func syncWithCurrentPlayback(currentItem: ProfileMediaItem?, preferFirstItem: Bool = false) {
        guard let currentItem else {
            if preferFirstItem, let first = lineup.first {
                nowPlaying = first
            }
            return
        }

        let key = key(forOwner: currentItem.ownerId, mediaId: currentItem.id)
        let track = trackLookup[key] ?? RadioTrack(media: currentItem, owner: ownerProfiles[currentItem.ownerId])
        trackLookup[key] = track
        nowPlaying = track
        if let index = lineup.firstIndex(where: { $0.id == track.id }) {
            currentQueueIndex = index
        } else {
            currentQueueIndex = nil
        }
    }

    private func key(forOwner ownerId: String, mediaId: String) -> String {
        "\(ownerId)|\(mediaId)"
    }
}
