import Foundation

struct UserReport: Identifiable, Codable, Equatable {
    let id: String
    let reportedUserId: String
    let reporterUserId: String
    let reason: Reason
    var details: String
    let createdAt: Date
    var evidencePhotoURLs: [URL]

    init(
        id: String = UUID().uuidString,
        reportedUserId: String,
        reporterUserId: String,
        reason: Reason,
        details: String = "",
        createdAt: Date = Date(),
        evidencePhotoURLs: [URL] = []
    ) {
        self.id = id
        self.reportedUserId = reportedUserId
        self.reporterUserId = reporterUserId
        self.reason = reason
        self.details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.evidencePhotoURLs = evidencePhotoURLs
    }
}

extension UserReport {
    enum Reason: String, CaseIterable, Codable, Identifiable {
        case spam
        case inappropriateContent
        case harassment
        case fraud
        case impersonation
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .spam:
                return "Spam or misleading"
            case .inappropriateContent:
                return "Inappropriate content"
            case .harassment:
                return "Harassment or abuse"
            case .fraud:
                return "Fraud or unsafe behavior"
            case .impersonation:
                return "Impersonation"
            case .other:
                return "Something else"
            }
        }

        var guidance: String {
            switch self {
            case .spam:
                return "Unwanted messages, promotions, or repeated solicitations."
            case .inappropriateContent:
                return "Profanity, offensive media, or other content that violates guidelines."
            case .harassment:
                return "Threats, bullying, or targeted harassment."
            case .fraud:
                return "Scams, payment issues, or unsafe conduct."
            case .impersonation:
                return "Pretending to be another person or business."
            case .other:
                return "Describe the issue you encountered."
            }
        }

        var requiresDetails: Bool {
            switch self {
            case .harassment, .fraud, .impersonation, .other:
                return true
            case .spam, .inappropriateContent:
                return false
            }
        }
    }

    static let mock = UserReport(
        reportedUserId: "reported-user",
        reporterUserId: "reporter-user",
        reason: .spam,
        details: "Received repeated unsolicited messages promoting unrelated services.",
        evidencePhotoURLs: [URL(string: "https://example.com/report/evidence.jpg")!]
    )
}
