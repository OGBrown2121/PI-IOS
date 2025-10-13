import Foundation

enum BookingFlowError: LocalizedError {
    case studioClosed
    case studioBlackout
    case roomUnavailable
    case engineerUnavailable
    case invalidDuration
    case missingEngineer
    case missingRoom

    var errorDescription: String? {
        switch self {
        case .studioClosed:
            return "The studio is closed at that time. Pick a different slot."
        case .studioBlackout:
            return "The studio is unavailable on that date."
        case .roomUnavailable:
            return "That room is already booked or blocked."
        case .engineerUnavailable:
            return "The engineer has a conflict at that time."
        case .invalidDuration:
            return "Please choose a duration between 30 minutes and 12 hours."
        case .missingEngineer:
            return "Select an engineer before booking."
        case .missingRoom:
            return "Select a room before booking."
        }
    }
}

struct BookingContext {
    let studio: Studio
    let rooms: [Room]
    let engineers: [UserProfile]
    let studioAvailability: [AvailabilityEntry]
}

struct BookingRequestInput {
    let artist: UserProfile
    let studio: Studio
    let engineer: UserProfile
    let room: Room
    let startDate: Date
    let durationMinutes: Int
    let notes: String
}

struct BookingQuote {
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
    let pricing: BookingPricing?
    let isInstant: Bool
    let autoApproval: BookingApprovalState
}

protocol BookingService {
    func loadContext(for studio: Studio, preferredEngineerId: String?) async throws -> BookingContext
    func quote(for request: BookingRequestInput) async throws -> BookingQuote
    func submit(request: BookingRequestInput) async throws -> Booking
    func loadBooking(withId id: String) async throws -> Booking?
    func fetchBookings(for participantId: String, role: BookingParticipantRole) async throws -> [Booking]
    func updateBooking(_ booking: Booking) async throws
    func validateReschedule(for booking: Booking, newStart: Date, durationMinutes: Int) async throws
}

struct DefaultBookingService: BookingService {
    private let firestore: any FirestoreService

    init(firestore: any FirestoreService) {
        self.firestore = firestore
    }

    func loadContext(for studio: Studio, preferredEngineerId: String?) async throws -> BookingContext {
        async let roomsTask = firestore.fetchRooms(for: studio.id)
        async let availabilityTask = firestore.fetchAvailability(scope: .studio, ownerId: studio.id)

        var engineerIDs = studio.approvedEngineerIds
        if let preferred = preferredEngineerId, engineerIDs.contains(preferred) == false {
            engineerIDs.append(preferred)
        }

        let engineers: [UserProfile]
        if engineerIDs.isEmpty {
            engineers = []
        } else {
            engineers = try await firestore.fetchUserProfiles(for: engineerIDs)
        }

        let rooms = try await roomsTask
        let studioAvailability = try await availabilityTask

        return BookingContext(
            studio: studio,
            rooms: rooms,
            engineers: engineers,
            studioAvailability: studioAvailability
        )
    }

    func quote(for request: BookingRequestInput) async throws -> BookingQuote {
        try validateDuration(request.durationMinutes)

        let endDate = request.startDate.addingTimeInterval(TimeInterval(request.durationMinutes * 60))
        let schedule = request.studio.operatingSchedule
        let calendar = calendar(for: schedule.timeZoneIdentifier)
        let timezone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? calendar.timeZone

        guard isWithinOperatingHours(start: request.startDate, end: endDate, schedule: schedule, calendar: calendar) else {
            throw BookingFlowError.studioClosed
        }

        guard isOutsideBlackoutDates(date: request.startDate, schedule: schedule, calendar: calendar) else {
            throw BookingFlowError.studioBlackout
        }

        try await ensureRoomIsFree(request: request, endDate: endDate, timezone: timezone)
        try await ensureEngineerIsFree(request: request, endDate: endDate, timezone: timezone)

        let pricing = resolvePricing(studio: request.studio, room: request.room, durationMinutes: request.durationMinutes)
        let approval = resolveApproval(studio: request.studio, engineer: request.engineer, startDate: request.startDate)
        let isInstant = approval.isFullyApproved

        return BookingQuote(
            startDate: request.startDate,
            endDate: endDate,
            durationMinutes: request.durationMinutes,
            pricing: pricing,
            isInstant: isInstant,
            autoApproval: approval
        )
    }

    func submit(request: BookingRequestInput) async throws -> Booking {
        let quote = try await quote(for: request)
        let booking = Booking(
            artistId: request.artist.id,
            studioId: request.studio.id,
            roomId: request.room.id,
            engineerId: request.engineer.id,
            status: quote.isInstant ? .confirmed : .pending,
            requestedStart: quote.startDate,
            requestedEnd: quote.endDate,
            confirmedStart: quote.isInstant ? quote.startDate : nil,
            confirmedEnd: quote.isInstant ? quote.endDate : nil,
            durationMinutes: quote.durationMinutes,
            pricing: quote.pricing,
            instantBook: quote.isInstant,
            approval: quote.autoApproval,
            notes: request.notes,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await firestore.createBooking(booking)

        return booking
    }

    func loadBooking(withId id: String) async throws -> Booking? {
        try await firestore.loadBooking(withId: id)
    }

    func fetchBookings(for participantId: String, role: BookingParticipantRole) async throws -> [Booking] {
        try await firestore.fetchBookings(for: participantId, role: role)
    }

    func updateBooking(_ booking: Booking) async throws {
        try await firestore.updateBooking(booking)
    }

    func validateReschedule(for booking: Booking, newStart: Date, durationMinutes: Int) async throws {
        try validateDuration(durationMinutes)

        let endDate = newStart.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let studios = try await firestore.fetchStudios()
        guard let studio = studios.first(where: { $0.id == booking.studioId }) else {
            throw BookingFlowError.roomUnavailable
        }

        let schedule = studio.operatingSchedule
        let calendar = calendar(for: schedule.timeZoneIdentifier)
        let timezone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? calendar.timeZone

        guard isWithinOperatingHours(start: newStart, end: endDate, schedule: schedule, calendar: calendar) else {
            throw BookingFlowError.studioClosed
        }

        guard isOutsideBlackoutDates(date: newStart, schedule: schedule, calendar: calendar) else {
            throw BookingFlowError.studioBlackout
        }

        async let availabilityTask = firestore.fetchAvailability(scope: .engineer, ownerId: booking.engineerId)
        async let engineerBookingsTask = fetchBookings(for: booking.engineerId, role: .engineer)

        let availabilityEntries = try await availabilityTask
        let engineerBookings = (try await engineerBookingsTask).filter { $0.id != booking.id }

        let blockingEntries = availabilityEntries
            .filter { $0.sourceBookingId != booking.id }
            .filter(isBlocking)

        guard isConflictFree(entries: blockingEntries, start: newStart, end: endDate, timezone: timezone) else {
            throw BookingFlowError.engineerUnavailable
        }

        guard conflicts(with: engineerBookings, studioId: booking.studioId, roomId: booking.roomId, engineerId: booking.engineerId, start: newStart, end: endDate) == false else {
            throw BookingFlowError.engineerUnavailable
        }
    }
}

private extension DefaultBookingService {
    func validateDuration(_ duration: Int) throws {
        guard duration >= 30 && duration <= 12 * 60 else {
            throw BookingFlowError.invalidDuration
        }
    }

    func calendar(for identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        if let timezone = TimeZone(identifier: identifier) {
            calendar.timeZone = timezone
        }
        return calendar
    }

    func isWithinOperatingHours(start: Date, end: Date, schedule: StudioOperatingSchedule, calendar: Calendar) -> Bool {
        guard schedule.recurringHours.isEmpty == false else { return true }
        let weekdayComponent = calendar.component(.weekday, from: start)
        let startMinutes = minutesFromMidnight(for: start, calendar: calendar)
        let endMinutes = minutesFromMidnight(for: end, calendar: calendar)
        let normalizedWeekday = (weekdayComponent + 6) % 7 // convert to 0-based where Sunday == 0

        for window in schedule.recurringHours where window.weekday == normalizedWeekday {
            let windowEnd = window.startTimeMinutes + window.durationMinutes
            if startMinutes >= window.startTimeMinutes && endMinutes <= windowEnd {
                return true
            }
        }
        return false
    }

    func isOutsideBlackoutDates(date: Date, schedule: StudioOperatingSchedule, calendar: Calendar) -> Bool {
        guard schedule.blackoutDates.isEmpty == false else { return true }
        return schedule.blackoutDates.contains { blackout in
            calendar.isDate(blackout, inSameDayAs: date)
        } == false
    }

    func ensureRoomIsFree(request: BookingRequestInput, endDate: Date, timezone: TimeZone) async throws {
        let availability = try await firestore.fetchAvailability(scope: .studio, ownerId: request.studio.id)
        let blockingEntries = availability.filter { entry in
            guard entry.roomId == nil || entry.roomId == request.room.id else { return false }
            return isBlocking(entry: entry)
        }

        guard isConflictFree(entries: blockingEntries, start: request.startDate, end: endDate, timezone: timezone) else {
            throw BookingFlowError.roomUnavailable
        }

        let existingBookings = try await firestore.fetchBookings(for: request.studio.id, role: .studio)
        guard conflicts(with: existingBookings, studioId: request.studio.id, roomId: request.room.id, engineerId: request.engineer.id, start: request.startDate, end: endDate) == false else {
            throw BookingFlowError.roomUnavailable
        }
    }

    func ensureEngineerIsFree(request: BookingRequestInput, endDate: Date, timezone: TimeZone) async throws {
        let availability = try await firestore.fetchAvailability(scope: .engineer, ownerId: request.engineer.id)
        let blockingEntries = availability.filter(isBlocking)

        guard isConflictFree(entries: blockingEntries, start: request.startDate, end: endDate, timezone: timezone) else {
            throw BookingFlowError.engineerUnavailable
        }

        let existingBookings = try await firestore.fetchBookings(for: request.engineer.id, role: .engineer)
        guard conflicts(with: existingBookings, studioId: request.studio.id, roomId: request.room.id, engineerId: request.engineer.id, start: request.startDate, end: endDate) == false else {
            throw BookingFlowError.engineerUnavailable
        }
    }

    func isBlocking(entry: AvailabilityEntry) -> Bool {
        switch entry.kind {
        case .block, .bookingHold, .selfBooking:
            return true
        case .recurring:
            return false
        }
    }

    func isConflictFree(entries: [AvailabilityEntry], start: Date, end: Date, timezone: TimeZone) -> Bool {
        let calendar = calendar(for: timezone.identifier)
        for entry in entries {
            if overlaps(entry: entry, start: start, end: end, calendar: calendar) {
                return false
            }
        }
        return true
    }

    func overlaps(entry: AvailabilityEntry, start: Date, end: Date, calendar: Calendar) -> Bool {
        if let entryStart = entry.startDate, let entryEnd = entry.endDate {
            return max(entryStart, start) < min(entryEnd, end)
        }

        guard let weekday = entry.weekday, let startMinutes = entry.startTimeMinutes else { return false }
        let duration = entry.durationMinutes
        let normalizedWeekday = (calendar.component(.weekday, from: start) + 6) % 7
        guard normalizedWeekday == weekday else { return false }

        let requestStartMinutes = minutesFromMidnight(for: start, calendar: calendar)
        let requestEndMinutes = minutesFromMidnight(for: end, calendar: calendar)
        let windowEnd = startMinutes + duration

        return requestStartMinutes < windowEnd && requestEndMinutes > startMinutes
    }

    func conflicts(
        with bookings: [Booking],
        studioId: String,
        roomId: String,
        engineerId: String,
        start: Date,
        end: Date
    ) -> Bool {
        let relevantStatuses: Set<BookingStatus> = [.pending, .confirmed, .rescheduled]
        for booking in bookings where relevantStatuses.contains(booking.status) {
            guard booking.studioId == studioId else { continue }
            if booking.roomId != roomId && booking.engineerId != engineerId {
                continue
            }
            let comparisonStart = booking.confirmedStart ?? booking.requestedStart
            let comparisonEnd = booking.confirmedEnd ?? booking.requestedEnd
            if max(comparisonStart, start) < min(comparisonEnd, end) {
                return true
            }
        }
        return false
    }

    func resolvePricing(studio: Studio, room: Room, durationMinutes: Int) -> BookingPricing? {
        let rate = room.hourlyRate ?? studio.hourlyRate
        guard let hourlyRate = rate else { return nil }
        let hours = Double(durationMinutes) / 60.0
        let total = hourlyRate * hours
        return BookingPricing(hourlyRate: hourlyRate, total: total)
    }

    func resolveApproval(studio: Studio, engineer: UserProfile, startDate: Date) -> BookingApprovalState {
        let engineerSettings = engineer.engineerSettings
        let calendar = Calendar(identifier: .gregorian)
        let mainStudioMatches: Bool
        if let mainStudio = engineerSettings.mainStudioId {
            mainStudioMatches = mainStudio == studio.id
        } else {
            mainStudioMatches = false
        }

        let engineerAllowsStudio = engineerSettings.allowOtherStudios || mainStudioMatches
        let canInstantBook = engineerSettings.canInstantBook && engineerAllowsStudio && studio.autoApproveRequests

        return BookingApprovalState(
            requiresStudioApproval: canInstantBook == false,
            requiresEngineerApproval: engineerSettings.canInstantBook == false || engineerAllowsStudio == false
        )
    }

    func minutesFromMidnight(for date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0
        return hours * 60 + minutes
    }
}
