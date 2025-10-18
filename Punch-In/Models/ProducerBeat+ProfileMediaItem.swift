import Foundation

extension ProducerBeat {
    var previewMediaItem: ProfileMediaItem? {
        guard let previewURL else { return nil }
        return ProfileMediaItem(
            id: "beat-\(id)",
            ownerId: producerId,
            title: title.isEmpty ? "Beat preview" : title,
            caption: summary,
            format: .audio,
            category: .song,
            mediaURL: previewURL,
            coverArtURL: artworkURL,
            durationSeconds: durationSeconds,
            isShared: true,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

