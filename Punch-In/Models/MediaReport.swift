import Foundation

/// Represents a user-submitted report for a specific media item.
struct MediaReport: Identifiable, Codable, Equatable {
    let id: String
    let mediaId: String
    let ownerId: String
    let reporterUserId: String
    let reason: UserReport.Reason
    var details: String
    let createdAt: Date
    var evidencePhotoURLs: [URL]

    init(
        id: String = UUID().uuidString,
        mediaId: String,
        ownerId: String,
        reporterUserId: String,
        reason: UserReport.Reason,
        details: String = "",
        createdAt: Date = Date(),
        evidencePhotoURLs: [URL] = []
    ) {
        self.id = id
        self.mediaId = mediaId
        self.ownerId = ownerId
        self.reporterUserId = reporterUserId
        self.reason = reason
        self.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.evidencePhotoURLs = evidencePhotoURLs
    }
}
