import Foundation
import FirebaseAuth

@MainActor
final class BookingFlowViewModel: ObservableObject {
    @Published var context: BookingContext?
    @Published var isLoading = false
    @Published var loadErrorMessage: String?
    @Published var quote: BookingQuote?
    @Published var quoteErrorMessage: String?
    @Published var selectedEngineer: UserProfile?
    @Published var selectedRoom: Room?
    @Published var startDate: Date
    @Published var durationMinutes: Int
    @Published var notes: String = ""
    @Published var isSubmitting = false
    @Published var submissionErrorMessage: String?
    @Published var submittedBooking: Booking?
    @Published private(set) var engineerAvailabilityLines: [EngineerAvailabilityLine] = []
    @Published private(set) var engineerAvailabilityMessage: String?
    @Published private(set) var isLoadingEngineerAvailability = false

    let studio: Studio
    let preferredEngineerId: String?

    private let bookingService: any BookingService
    private let firestoreService: any FirestoreService
    private let currentUserProvider: () -> UserProfile?

    init(
        studio: Studio,
        preferredEngineerId: String?,
        bookingService: any BookingService,
        firestoreService: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.studio = studio
        self.preferredEngineerId = preferredEngineerId
        self.bookingService = bookingService
        self.firestoreService = firestoreService
        self.currentUserProvider = currentUserProvider
        self.startDate = BookingFlowViewModel.defaultStartDate()
        self.durationMinutes = 120
    }

    func load() async {
        guard isLoading == false else { return }
        isLoading = true
        do {
            let context = try await bookingService.loadContext(for: studio, preferredEngineerId: preferredEngineerId)
            let rooms: [Room]
            if context.rooms.isEmpty {
                if let declaredCount = studio.rooms, declaredCount > 0 {
                    rooms = (1...declaredCount).map { index in
                        Room(
                            studioId: studio.id,
                            name: "Room \(index)",
                            hourlyRate: studio.hourlyRate,
                            isDefault: index == 1
                        )
                    }
                } else {
                    rooms = [Room(
                        studioId: studio.id,
                        name: "Main Room",
                        hourlyRate: studio.hourlyRate,
                        isDefault: true
                    )]
                }
            } else {
                rooms = context.rooms
            }

            let resolvedContext = BookingContext(
                studio: context.studio,
                rooms: rooms,
                engineers: context.engineers,
                studioAvailability: context.studioAvailability
            )

            self.context = resolvedContext

            if let engineer = context.engineers.first(where: { $0.id == preferredEngineerId }) ?? context.engineers.first {
                selectedEngineer = engineer
            }
            if let firstRoom = rooms.first {
                selectedRoom = firstRoom
            }
            loadErrorMessage = nil
            await refreshQuote()
            await refreshEngineerAvailability()
        } catch {
            loadErrorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func refreshQuote() async {
        guard let artist = currentUserProvider() else { return }
        guard let engineer = selectedEngineer else {
            quote = nil
            quoteErrorMessage = BookingFlowError.missingEngineer.errorDescription
            return
        }
        guard let room = selectedRoom else {
            quote = nil
            quoteErrorMessage = BookingFlowError.missingRoom.errorDescription
            return
        }

        do {
            let request = BookingRequestInput(
                artist: artist,
                studio: studio,
                engineer: engineer,
                room: room,
                startDate: startDate,
                durationMinutes: durationMinutes,
                notes: notes
            )
            let newQuote = try await bookingService.quote(for: request)
            quoteErrorMessage = nil
            quote = newQuote
        } catch {
            quote = nil
            quoteErrorMessage = error.localizedDescription
        }
    }

    func submit() async {
        guard isSubmitting == false else { return }
        guard let artist = currentUserProvider() else {
            submissionErrorMessage = "You need an account to book."
            return
        }
        guard let engineer = selectedEngineer else {
            submissionErrorMessage = BookingFlowError.missingEngineer.errorDescription
            return
        }
        guard let room = selectedRoom else {
            submissionErrorMessage = BookingFlowError.missingRoom.errorDescription
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let request = BookingRequestInput(
                artist: artist,
                studio: studio,
                engineer: engineer,
                room: room,
                startDate: startDate,
                durationMinutes: durationMinutes,
                notes: notes
            )
            #if DEBUG
            let currentUid = Auth.auth().currentUser?.uid ?? "(nil)"
            print("[BookingFlow] submit artistId=\(artist.id) currentUser=\(currentUid)")
            #endif
            let booking = try await bookingService.submit(request: request)
            submittedBooking = booking
            submissionErrorMessage = nil
        } catch {
            submissionErrorMessage = error.localizedDescription
        }
    }

    func durationOptions() -> [Int] {
        stride(from: 60, through: 6 * 60, by: 30).map { $0 }
    }

    func refreshEngineerAvailability() async {
        guard isLoadingEngineerAvailability == false else { return }
        guard let _ = context else { return }
        guard let engineer = selectedEngineer else {
            engineerAvailabilityLines = []
            engineerAvailabilityMessage = "Select an engineer to view availability."
            return
        }

        isLoadingEngineerAvailability = true
        engineerAvailabilityMessage = nil
        engineerAvailabilityLines = []
        defer { isLoadingEngineerAvailability = false }

        do {
            async let availabilityTask = firestoreService.fetchAvailability(scope: .engineer, ownerId: engineer.id)
            async let engineerBookingsTask = bookingService.fetchBookings(for: engineer.id, role: .engineer)
            async let roomBookingsTask = bookingService.fetchBookings(for: studio.id, role: .studio)

            let availabilityEntries = try await availabilityTask
            let engineerBookings = try await engineerBookingsTask
            let studioBookings = try await roomBookingsTask

            let lines = computeEngineerAvailability(
                engineer: engineer,
                availabilityEntries: availabilityEntries,
                engineerBookings: engineerBookings,
                studioBookings: studioBookings
            )

            if lines.isEmpty {
                engineerAvailabilityMessage = "Fully booked on selected day."
            }
            engineerAvailabilityLines = lines
        } catch {
            engineerAvailabilityMessage = error.localizedDescription
        }
    }

    private static func defaultStartDate() -> Date {
        let now = Date()
        let calendar = Calendar.current
        if let nextHour = calendar.date(bySettingHour: calendar.component(.hour, from: now) + 1, minute: 0, second: 0, of: now) {
            return nextHour
        }
        return now.addingTimeInterval(3600)
    }
}

extension BookingFlowViewModel {
    struct EngineerAvailabilityLine: Identifiable, Equatable {
        let id: UUID = UUID()
        let title: String
        let subtitle: String
    }
}

private extension BookingFlowViewModel {
    func computeEngineerAvailability(
        engineer: UserProfile,
        availabilityEntries: [AvailabilityEntry],
        engineerBookings: [Booking],
        studioBookings: [Booking]
    ) -> [EngineerAvailabilityLine] {
        let timezone = TimeZone(identifier: studio.operatingSchedule.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let dayStart = calendar.startOfDay(for: startDate)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }

        if studio.operatingSchedule.blackoutDates.contains(where: { calendar.isDate($0, inSameDayAs: dayStart) }) {
            return []
        }

        let baseWindows = AvailabilityWindowCalculator.baseWindows(
            schedule: studio.operatingSchedule,
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: calendar
        )
        guard baseWindows.isEmpty == false else { return [] }

        var openIntervals = baseWindows

        let busyIntervals = busyIntervalsForEngineer(
            availabilityEntries: availabilityEntries,
            engineerBookings: engineerBookings,
            studioBookings: studioBookings,
            dayStart: dayStart,
            dayEnd: dayEnd,
            calendar: calendar
        )

        for interval in busyIntervals {
            openIntervals = AvailabilityWindowCalculator.subtract(openIntervals, removing: interval)
        }

        let formatter = AvailabilityWindowCalculator.timeFormatter(timezone: timezone)

        let windowTitle = selectedRoom?.name ?? "Available"

        let labels = openIntervals
            .sorted { $0.start < $1.start }
            .map { interval -> EngineerAvailabilityLine in
                let startLabel = formatter.string(from: interval.start)
                let adjustedEnd: Date
                if interval.end >= dayEnd {
                    adjustedEnd = (calendar.date(byAdding: .minute, value: -1, to: dayEnd) ?? interval.end)
                } else {
                    adjustedEnd = interval.end
                }
                let endLabel = formatter.string(from: adjustedEnd)
                return EngineerAvailabilityLine(title: windowTitle, subtitle: "\(startLabel) – \(endLabel)")
            }

        return labels
    }

    func busyIntervalsForEngineer(
        availabilityEntries: [AvailabilityEntry],
        engineerBookings: [Booking],
        studioBookings: [Booking],
        dayStart: Date,
        dayEnd: Date,
        calendar: Calendar
    ) -> [DateInterval] {
        var busy: [DateInterval] = []

        let relevantStatuses: Set<BookingStatus> = [.pending, .confirmed, .rescheduled]

        for booking in engineerBookings where relevantStatuses.contains(booking.status) {
            if let interval = AvailabilityWindowCalculator.clampedInterval(
                for: booking,
                dayStart: dayStart,
                dayEnd: dayEnd
            ) {
                busy.append(interval)
            }
        }

        if let selectedRoom = selectedRoom {
            for booking in studioBookings where booking.roomId == selectedRoom.id && relevantStatuses.contains(booking.status) {
                if let interval = AvailabilityWindowCalculator.clampedInterval(
                    for: booking,
                    dayStart: dayStart,
                    dayEnd: dayEnd
                ) {
                    busy.append(interval)
                }
            }
        }

        for entry in availabilityEntries {
            switch entry.kind {
            case .block, .bookingHold, .selfBooking:
                if let interval = AvailabilityWindowCalculator.interval(
                    for: entry,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar
                ) {
                    busy.append(interval)
                }
            case .recurring:
                if let interval = AvailabilityWindowCalculator.recurringInterval(
                    for: entry,
                    dayStart: dayStart,
                    dayEnd: dayEnd,
                    calendar: calendar
                ) {
                    // Treat recurring blocks as unavailable time
                    busy.append(interval)
                }
            }
        }

        return AvailabilityWindowCalculator.mergeOverlapping(busy)
    }
}
