import Foundation

@MainActor
final class ProfileMediaDetailViewModel: ObservableObject {
    @Published private(set) var media: ProfileMediaItem
    @Published var isUpdatingRating = false
    @Published var ratingError: String?

    private let firestoreService: any FirestoreService
    private let currentUserProvider: () -> UserProfile?

    init(media: ProfileMediaItem, firestoreService: any FirestoreService, currentUserProvider: @escaping () -> UserProfile?) {
        self.media = media
        self.firestoreService = firestoreService
        self.currentUserProvider = currentUserProvider
    }

    var currentUser: UserProfile? {
        currentUserProvider()
    }

    var isOwner: Bool {
        currentUser?.id == media.ownerId
    }

    var userRating: Int? {
        media.rating(for: currentUser?.id)
    }

    func submitRating(_ rating: Int) async {
        guard let user = currentUser else {
            ratingError = "You need to sign in to rate this media."
            return
        }

        isUpdatingRating = true
        ratingError = nil
        let updated = media.updatingRating(for: user.id, value: rating)

        do {
            try await firestoreService.submitMediaRating(
                ownerId: media.ownerId,
                mediaId: media.id,
                reviewerId: user.id,
                rating: rating
            )
            media = updated
        } catch {
            ratingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isUpdatingRating = false
    }

    func removeRating() async {
        guard let user = currentUser else { return }
        isUpdatingRating = true
        let updated = media.updatingRating(for: user.id, value: nil)
        do {
            try await firestoreService.deleteMediaRating(
                ownerId: media.ownerId,
                mediaId: media.id,
                reviewerId: user.id
            )
            media = updated
        } catch {
            ratingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isUpdatingRating = false
    }

    func refresh(with item: ProfileMediaItem) {
        guard item.id == media.id else { return }
        media = item
    }

    func makeDraft() -> ProfileMediaDraft {
        ProfileMediaDraft(mediaItem: media, ownerId: media.ownerId)
    }
}
