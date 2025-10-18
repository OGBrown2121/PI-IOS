import Foundation

/// Represents a listener "like" for a radio-eligible media item.
struct RadioLike: Identifiable, Hashable {
    var id: String {
        "\(ownerId)|\(mediaId)|\(userId)"
    }

    let ownerId: String
    let mediaId: String
    let userId: String
    let createdAt: Date

    init(ownerId: String, mediaId: String, userId: String, createdAt: Date = Date()) {
        self.ownerId = ownerId
        self.mediaId = mediaId
        self.userId = userId
        self.createdAt = createdAt
    }
}
