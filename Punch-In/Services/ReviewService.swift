import Foundation

protocol ReviewService {
    func fetchReviews(for revieweeId: String, kind: ReviewSubjectKind) async throws -> [Review]
    func fetchReviewsAuthored(by reviewerId: String) async throws -> [Review]
    func submitReview(_ review: Review) async throws
}

struct DefaultReviewService: ReviewService {
    private let firestore: any FirestoreService

    init(firestore: any FirestoreService) {
        self.firestore = firestore
    }

    func fetchReviews(for revieweeId: String, kind: ReviewSubjectKind) async throws -> [Review] {
        try await firestore.fetchReviews(for: revieweeId, kind: kind)
    }

    func fetchReviewsAuthored(by reviewerId: String) async throws -> [Review] {
        try await firestore.fetchReviewsAuthored(by: reviewerId)
    }

    func submitReview(_ review: Review) async throws {
        try await firestore.upsertReview(review)
    }
}

struct MockReviewService: ReviewService {
    var reviewsByReviewee: [String: [ReviewSubjectKind: [Review]]] = [:]
    var reviewsByReviewer: [String: [Review]] = [:]

    func fetchReviews(for revieweeId: String, kind: ReviewSubjectKind) async throws -> [Review] {
        reviewsByReviewee[revieweeId]?[kind] ?? []
    }

    func fetchReviewsAuthored(by reviewerId: String) async throws -> [Review] {
        reviewsByReviewer[reviewerId] ?? []
    }

    func submitReview(_ review: Review) async throws {
        // No-op mock writes
    }
}
