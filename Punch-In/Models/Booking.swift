import Foundation

enum BookingStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case confirmed
    case completed
    case cancelled
    case rescheduled

    var id: String { rawValue }

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled:
            return true
        case .pending, .confirmed, .rescheduled:
            return false
        }
    }
}

enum BookingParticipantRole: String, Codable, CaseIterable {
    case artist
    case studio
    case engineer
}

struct BookingPricing: Codable, Equatable {
    var hourlyRate: Double
    var total: Double
    var currency: String

    init(hourlyRate: Double, total: Double, currency: String = "USD") {
        self.hourlyRate = hourlyRate
        self.total = total
        self.currency = currency
    }
}

struct BookingApprovalState: Codable, Equatable {
    var requiresStudioApproval: Bool
    var requiresEngineerApproval: Bool
    var resolvedBy: String?
    var resolvedAt: Date?

    init(
        requiresStudioApproval: Bool,
        requiresEngineerApproval: Bool,
        resolvedBy: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.requiresStudioApproval = requiresStudioApproval
        self.requiresEngineerApproval = requiresEngineerApproval
        self.resolvedBy = resolvedBy
        self.resolvedAt = resolvedAt
    }

    var isFullyApproved: Bool {
        !requiresStudioApproval && !requiresEngineerApproval
    }
}

struct BookingTimelineEvent: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case statusChange
        case note
        case reminder
        case reschedule
    }

    var id: String
    var kind: Kind
    var message: String
    var createdBy: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        kind: Kind,
        message: String,
        createdBy: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.createdBy = createdBy
        self.createdAt = createdAt
    }
}

struct Booking: Identifiable, Codable, Equatable {
    var id: String
    var artistId: String
    var studioId: String
    var roomId: String
    var engineerId: String
    var status: BookingStatus
    var requestedStart: Date
    var requestedEnd: Date
    var confirmedStart: Date?
    var confirmedEnd: Date?
    var durationMinutes: Int
    var pricing: BookingPricing?
    var instantBook: Bool
    var approval: BookingApprovalState
    var conversationId: String?
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        artistId: String,
        studioId: String,
        roomId: String,
        engineerId: String,
        status: BookingStatus = .pending,
        requestedStart: Date,
        requestedEnd: Date,
        confirmedStart: Date? = nil,
        confirmedEnd: Date? = nil,
        durationMinutes: Int,
        pricing: BookingPricing? = nil,
        instantBook: Bool = false,
        approval: BookingApprovalState,
        conversationId: String? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.artistId = artistId
        self.studioId = studioId
        self.roomId = roomId
        self.engineerId = engineerId
        self.status = status
        self.requestedStart = requestedStart
        self.requestedEnd = requestedEnd
        self.confirmedStart = confirmedStart
        self.confirmedEnd = confirmedEnd
        self.durationMinutes = durationMinutes
        self.pricing = pricing
        self.instantBook = instantBook
        self.approval = approval
        self.conversationId = conversationId
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isPending: Bool { status == .pending }
    var isConfirmed: Bool { status == .confirmed }
    var timeWindow: ClosedRange<Date> { requestedStart...requestedEnd }

    func updatingStatus(_ newStatus: BookingStatus, actorId: String) -> (Booking, BookingTimelineEvent) {
        var updated = self
        updated.status = newStatus
        updated.updatedAt = Date()
        let event = BookingTimelineEvent(
            kind: .statusChange,
            message: "Status changed to \(newStatus.rawValue.capitalized)",
            createdBy: actorId
        )
        return (updated, event)
    }
}

extension Booking {
    static func mock(
        artistId: String,
        studioId: String,
        roomId: String,
        engineerId: String,
        status: BookingStatus = .pending,
        instant: Bool = false
    ) -> Booking {
        let start = Date().addingTimeInterval(4 * 3600)
        let end = start.addingTimeInterval(2 * 3600)
        let approval = BookingApprovalState(
            requiresStudioApproval: !instant,
            requiresEngineerApproval: !instant
        )
        return Booking(
            artistId: artistId,
            studioId: studioId,
            roomId: roomId,
            engineerId: engineerId,
            status: status,
            requestedStart: start,
            requestedEnd: end,
            durationMinutes: 120,
            pricing: BookingPricing(hourlyRate: 85, total: 170),
            instantBook: instant,
            approval: approval
        )
    }
}
