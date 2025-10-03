import Foundation

enum ReviewSubjectKind: String, Codable, CaseIterable {
    case studio
    case artist
    case engineer
    case studioOwner
}

struct Review: Identifiable, Codable, Equatable {
    let id: String
    let bookingId: String
    let reviewerId: String
    let reviewerAccountType: AccountType
    let revieweeId: String
    let revieweeKind: ReviewSubjectKind
    var rating: Int
    var comment: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        bookingId: String,
        reviewerId: String,
        reviewerAccountType: AccountType,
        revieweeId: String,
        revieweeKind: ReviewSubjectKind,
        rating: Int,
        comment: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookingId = bookingId
        self.reviewerId = reviewerId
        self.reviewerAccountType = reviewerAccountType
        self.revieweeId = revieweeId
        self.revieweeKind = revieweeKind
        self.rating = rating
        self.comment = comment
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Review {
    var isEditable: Bool {
        rating >= 1 && rating <= 5
    }

    func updating(rating: Int, comment: String) -> Review {
        Review(
            id: id,
            bookingId: bookingId,
            reviewerId: reviewerId,
            reviewerAccountType: reviewerAccountType,
            revieweeId: revieweeId,
            revieweeKind: revieweeKind,
            rating: rating,
            comment: comment,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

extension Review {
    static let mock = Review(
        bookingId: UUID().uuidString,
        reviewerId: UUID().uuidString,
        reviewerAccountType: .artist,
        revieweeId: UUID().uuidString,
        revieweeKind: .studio,
        rating: 5,
        comment: "Amazing vibe and gear."
    )
}
