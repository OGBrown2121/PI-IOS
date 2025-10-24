import Foundation

enum VideoProjectRequestStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case awaitingRequesterDecision
    case scheduled
    case declined

    var id: String { rawValue }

    var isFinal: Bool {
        switch self {
        case .scheduled, .declined:
            return true
        case .pending, .awaitingRequesterDecision:
            return false
        }
    }
}

struct VideoProjectRequest: Identifiable, Codable, Equatable {
    var id: String
    var videographerId: String
    var requesterId: String
    var requesterDisplayName: String
    var requesterUsername: String
    var startDate: Date
    var durationMinutes: Int
    var shootLocations: [String]
    var projectDetails: String
    var quotedHourlyRate: Double?
    var status: VideoProjectRequestStatus
    var createdAt: Date
    var updatedAt: Date
    var decisionAt: Date?
    var decisionBy: String?
    var conversationId: String?
    var videographerRespondedAt: Date?
    var requesterDecisionAt: Date?

    init(
        id: String = UUID().uuidString,
        videographerId: String,
        requesterId: String,
        requesterDisplayName: String,
        requesterUsername: String,
        startDate: Date,
        durationMinutes: Int,
        shootLocations: [String],
        projectDetails: String,
        quotedHourlyRate: Double? = nil,
        status: VideoProjectRequestStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        decisionAt: Date? = nil,
        decisionBy: String? = nil,
        conversationId: String? = nil,
        videographerRespondedAt: Date? = nil,
        requesterDecisionAt: Date? = nil
    ) {
        self.id = id
        self.videographerId = videographerId
        self.requesterId = requesterId
        self.requesterDisplayName = requesterDisplayName
        self.requesterUsername = requesterUsername
        self.startDate = startDate
        self.durationMinutes = durationMinutes
        self.shootLocations = shootLocations
        self.projectDetails = projectDetails
        self.quotedHourlyRate = quotedHourlyRate
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.decisionAt = decisionAt
        self.decisionBy = decisionBy
        self.conversationId = conversationId
        self.videographerRespondedAt = videographerRespondedAt
        self.requesterDecisionAt = requesterDecisionAt
    }

    var isPending: Bool {
        status == .pending
    }

    var requiresRequesterApproval: Bool {
        status == .awaitingRequesterDecision
    }

    var isAwaitingRequesterDecision: Bool {
        status == .awaitingRequesterDecision
    }

    var isScheduled: Bool {
        status == .scheduled
    }

    var proposedTimeRange: ClosedRange<Date> {
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return startDate...endDate
    }

    var requesterApprovedQuoteAt: Date? {
        get { requesterDecisionAt }
        set { requesterDecisionAt = newValue }
    }
}
