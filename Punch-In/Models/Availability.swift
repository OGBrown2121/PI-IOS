import Foundation

enum AvailabilityKind: String, Codable, CaseIterable, Identifiable {
    case recurring
    case block
    case bookingHold
    case selfBooking

    var id: String { rawValue }
}

enum AvailabilityScope: String, Codable, Hashable {
    case studio
    case engineer
}

struct RecurringTimeRange: Identifiable, Codable, Equatable {
    var id: String
    var weekday: Int // 0 = Sunday
    var startTimeMinutes: Int
    var durationMinutes: Int

    init(
        id: String = UUID().uuidString,
        weekday: Int,
        startTimeMinutes: Int,
        durationMinutes: Int
    ) {
        self.id = id
        self.weekday = weekday
        self.startTimeMinutes = startTimeMinutes
        self.durationMinutes = durationMinutes
    }
}

struct AvailabilityEntry: Identifiable, Codable, Equatable {
    var id: String
    var kind: AvailabilityKind
    var ownerId: String
    var studioId: String?
    var roomId: String?
    var engineerId: String?
    var weekday: Int?
    var startTimeMinutes: Int?
    var durationMinutes: Int
    var startDate: Date?
    var endDate: Date?
    var sourceBookingId: String?
    var createdBy: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        kind: AvailabilityKind,
        ownerId: String,
        studioId: String? = nil,
        roomId: String? = nil,
        engineerId: String? = nil,
        weekday: Int? = nil,
        startTimeMinutes: Int? = nil,
        durationMinutes: Int,
        startDate: Date? = nil,
        endDate: Date? = nil,
        sourceBookingId: String? = nil,
        createdBy: String,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.ownerId = ownerId
        self.studioId = studioId
        self.roomId = roomId
        self.engineerId = engineerId
        self.weekday = weekday
        self.startTimeMinutes = startTimeMinutes
        self.durationMinutes = durationMinutes
        self.startDate = startDate
        self.endDate = endDate
        self.sourceBookingId = sourceBookingId
        self.createdBy = createdBy
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isRecurring: Bool { weekday != nil && startTimeMinutes != nil }
}

struct StudioOperatingSchedule: Codable, Equatable {
    var timeZoneIdentifier: String
    var recurringHours: [RecurringTimeRange]
    var blackoutDates: [Date]

    init(
        timeZoneIdentifier: String = TimeZone.current.identifier,
        recurringHours: [RecurringTimeRange] = [],
        blackoutDates: [Date] = []
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.recurringHours = recurringHours
        self.blackoutDates = blackoutDates
    }
}
