import Foundation

@MainActor
final class BookingInboxViewModel: ObservableObject {
    enum ViewerRole {
        case unknown
        case unsupported
        case engineer
        case artist
        case studioOwner
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case list
        case calendar

        var id: String { rawValue }

        var title: String {
            switch self {
            case .list:
                return "List"
            case .calendar:
                return "Calendar"
            }
        }
    }

    @Published private(set) var viewerRole: ViewerRole = .unknown
    @Published private(set) var pendingApprovals: [Booking] = []
    @Published private(set) var scheduledBookings: [Booking] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var displayMode: DisplayMode = .list
    @Published var selectedCalendarDate: Date {
        didSet {
            let normalized = calendar.startOfDay(for: selectedCalendarDate)
            if selectedCalendarDate != normalized {
                selectedCalendarDate = normalized
            }
        }
    }
    @Published private(set) var calendarBookings: [Booking] = []
    @Published private var actionInFlight: Set<String> = []
    @Published private var userNames: [String: String] = [:]
    @Published private var studioNames: [String: String] = [:]
    @Published private var roomNames: [String: String] = [:]

    private let bookingService: any BookingService
    private let firestore: any FirestoreService
    private let currentUserProvider: () -> UserProfile?
    private let calendar: Calendar
    private var fetchedRoomsForStudios: Set<String> = []

    init(
        bookingService: any BookingService,
        firestoreService: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.bookingService = bookingService
        self.firestore = firestoreService
        self.currentUserProvider = currentUserProvider
        let calendar = Calendar.current
        self.calendar = calendar
        self.selectedCalendarDate = calendar.startOfDay(for: Date())
    }

    func load() async {
        guard isLoading == false else { return }
        await refresh()
    }

    func refresh() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        guard let user = currentUserProvider() else {
            viewerRole = .unknown
            errorMessage = "You need an account to view bookings."
            pendingApprovals = []
            scheduledBookings = []
            calendarBookings = []
            return
        }

        viewerRole = role(for: user.accountType)
        errorMessage = nil

        switch viewerRole {
        case .engineer:
            await loadEngineerBookings(for: user)
        case .artist:
            await loadArtistBookings(for: user)
        case .studioOwner:
            await loadStudioBookings(for: user)
        case .unsupported, .unknown:
            pendingApprovals = []
            scheduledBookings = []
            calendarBookings = []
        }
    }

    func isPerformingAction(for booking: Booking) -> Bool {
        actionInFlight.contains(booking.id)
    }

    func canAct(on booking: Booking) -> Bool {
        guard booking.status == .pending else { return false }
        switch viewerRole {
        case .engineer:
            return booking.approval.requiresEngineerApproval
        case .studioOwner:
            return booking.approval.requiresStudioApproval
        default:
            return false
        }
    }

    func approve(_ booking: Booking) async {
        guard let user = currentUserProvider() else { return }
        #if DEBUG
        print("[BookingInbox] approve tapped by role=\(viewerRole) user=\(user.id) booking=\(booking.id))")
        #endif

        switch viewerRole {
        case .engineer:
            await performMutation(on: booking) { booking in
                var updated = booking
                var approval = updated.approval
                approval.requiresEngineerApproval = false
                approval.resolvedBy = user.id
                approval.resolvedAt = Date()
                updated.approval = approval

                if approval.requiresStudioApproval == false {
                    updated.status = .confirmed
                    updated.confirmedStart = updated.requestedStart
                    updated.confirmedEnd = updated.requestedEnd
                }

                updated.updatedAt = Date()
                return updated
            }
        case .studioOwner:
            await performMutation(on: booking) { booking in
                var updated = booking
                var approval = updated.approval
                approval.requiresStudioApproval = false
                approval.resolvedBy = user.id
                approval.resolvedAt = Date()
                updated.approval = approval

                if approval.requiresEngineerApproval == false {
                    updated.status = .confirmed
                    updated.confirmedStart = updated.requestedStart
                    updated.confirmedEnd = updated.requestedEnd
                }

                updated.updatedAt = Date()
                return updated
            }
        default:
            return
        }
    }

    func decline(_ booking: Booking) async {
        guard let user = currentUserProvider() else { return }
        #if DEBUG
        print("[BookingInbox] decline tapped by role=\(viewerRole) user=\(user.id) booking=\(booking.id))")
        #endif

        switch viewerRole {
        case .engineer:
            await performMutation(on: booking) { booking in
                var updated = booking
                var approval = updated.approval
                approval.requiresEngineerApproval = false
                approval.resolvedBy = user.id
                approval.resolvedAt = Date()
                updated.approval = approval
                updated.status = .cancelled
                updated.confirmedStart = nil
                updated.confirmedEnd = nil
                updated.updatedAt = Date()
                return updated
            }
        case .studioOwner:
            await performMutation(on: booking) { booking in
                var updated = booking
                var approval = updated.approval
                approval.requiresStudioApproval = false
                approval.requiresEngineerApproval = false
                approval.resolvedBy = user.id
                approval.resolvedAt = Date()
                updated.approval = approval
                updated.status = .cancelled
                updated.confirmedStart = nil
                updated.confirmedEnd = nil
                updated.updatedAt = Date()
                return updated
            }
        default:
            return
        }
    }

    private func performMutation(on booking: Booking, transform: (Booking) -> Booking) async {
        guard actionInFlight.contains(booking.id) == false else { return }
        actionInFlight.insert(booking.id)
        defer { actionInFlight.remove(booking.id) }

        let updatedBooking = transform(booking)
        do {
            try await bookingService.updateBooking(updatedBooking)
            pendingApprovals.removeAll { $0.id == booking.id }
            scheduledBookings.removeAll { $0.id == booking.id }
            await refresh()
        } catch {
            #if DEBUG
            print("[BookingInbox] mutation failed for booking=\(booking.id) role=\(viewerRole) error=\(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }

    private func loadEngineerBookings(for user: UserProfile) async {
        do {
            let bookings = try await bookingService.fetchBookings(for: user.id, role: .engineer)
            let sorted = bookings.sorted { $0.requestedStart < $1.requestedStart }
            let pending = sorted.filter { booking in
                booking.status == .pending && booking.approval.requiresEngineerApproval
            }
            let pendingIds = Set(pending.map { $0.id })
            let upcoming = sorted.filter { booking in
                booking.status != .cancelled
                    && booking.requestedEnd > Date()
                    && pendingIds.contains(booking.id) == false
            }
            await resolveMetadata(for: sorted)
            updateCalendarData(with: sorted)
            pendingApprovals = pending
            scheduledBookings = upcoming
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingApprovals = []
            scheduledBookings = []
        }
    }

    private func loadArtistBookings(for user: UserProfile) async {
        do {
            let bookings = try await bookingService.fetchBookings(for: user.id, role: .artist)
            scheduledBookings = bookings.sorted { $0.requestedStart < $1.requestedStart }
            await resolveMetadata(for: bookings)
            updateCalendarData(with: scheduledBookings)
            pendingApprovals = []
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            scheduledBookings = []
            pendingApprovals = []
        }
    }

    private func loadStudioBookings(for user: UserProfile) async {
        do {
            let studios = try await firestore.fetchStudios()
            let ownedStudios = studios.filter { $0.ownerId == user.id }
            #if DEBUG
            print("[BookingInbox] studio owner=\(user.id) owns: \(ownedStudios.map { $0.id }))")
            #endif

            guard ownedStudios.isEmpty == false else {
                pendingApprovals = []
                scheduledBookings = []
                errorMessage = "Add a studio to receive booking requests."
                updateCalendarData(with: [])
                return
            }

            var allBookings: [Booking] = []
            for studio in ownedStudios {
                studioNames[studio.id] = studio.name
                let bookings = try await bookingService.fetchBookings(for: studio.id, role: .studio)
                allBookings.append(contentsOf: bookings)
            }

            let sorted = allBookings.sorted { $0.requestedStart < $1.requestedStart }
            let pending = sorted.filter { $0.status == .pending && $0.approval.requiresStudioApproval }
            let pendingIds = Set(pending.map { $0.id })
            let upcoming = sorted.filter { booking in
                booking.status != .cancelled
                    && booking.requestedEnd > Date()
                    && pendingIds.contains(booking.id) == false
            }

            await resolveMetadata(for: sorted, ownedStudios: ownedStudios)
            updateCalendarData(with: sorted)

            pendingApprovals = pending
            scheduledBookings = upcoming
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingApprovals = []
            scheduledBookings = []
        }
    }

    private func role(for accountType: AccountType) -> ViewerRole {
        switch accountType {
        case .engineer:
            return .engineer
        case .artist:
            return .artist
        case .studioOwner:
            return .studioOwner
        }
    }

    func bookings(for date: Date) -> [Booking] {
        let day = calendar.startOfDay(for: date)
        return calendarBookings
            .filter { calendar.isDate($0.requestedStart, inSameDayAs: day) }
            .sorted { $0.requestedStart < $1.requestedStart }
    }

    var calendarDaySummaries: [CalendarDaySummary] {
        let grouped = Dictionary(grouping: calendarBookings) { calendar.startOfDay(for: $0.requestedStart) }
        return grouped.keys
            .sorted()
            .map { date in
                let bookings = grouped[date]?.sorted { $0.requestedStart < $1.requestedStart } ?? []
                return CalendarDaySummary(date: date, bookings: bookings)
            }
    }

    private func updateCalendarData(with bookings: [Booking]) {
        calendarBookings = bookings

        guard bookings.isEmpty == false else {
            selectedCalendarDate = calendar.startOfDay(for: Date())
            return
        }

        let availableDays = Array(Set(bookings.map { calendar.startOfDay(for: $0.requestedStart) })).sorted()
        guard let firstDay = availableDays.first else { return }

        let currentSelection = calendar.startOfDay(for: selectedCalendarDate)
        if availableDays.contains(where: { calendar.isDate($0, inSameDayAs: currentSelection) }) == false {
            let today = calendar.startOfDay(for: Date())
            let next = availableDays.first(where: { $0 >= today }) ?? firstDay
            selectedCalendarDate = next
        }
    }

    private func resolveMetadata(for bookings: [Booking], ownedStudios: [Studio] = []) async {
        guard bookings.isEmpty == false else { return }

        for studio in ownedStudios {
            studioNames[studio.id] = studio.name
        }

        let userIds = Set(bookings.flatMap { [$0.artistId, $0.engineerId] })
        let missingUserIds = userIds.filter { userNames[$0] == nil }
        if missingUserIds.isEmpty == false {
            do {
                let profiles = try await firestore.fetchUserProfiles(for: Array(missingUserIds))
                for profile in profiles {
                    let name = profile.displayName.isEmpty ? profile.username : profile.displayName
                    userNames[profile.id] = name
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        let studioIds = Set(bookings.map { $0.studioId })
        let missingStudios = studioIds.filter { studioNames[$0] == nil }
        if missingStudios.isEmpty == false {
            do {
                let studios = try await firestore.fetchStudios()
                for studio in studios where missingStudios.contains(studio.id) {
                    studioNames[studio.id] = studio.name
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        let roomIds = Set(bookings.map { $0.roomId })
        let missingRoomIds = roomIds.filter { roomNames[$0] == nil }
        let studiosNeedingRooms = Set(bookings
            .filter { missingRoomIds.contains($0.roomId) }
            .map { $0.studioId })

        for studioId in studiosNeedingRooms where fetchedRoomsForStudios.contains(studioId) == false {
            fetchedRoomsForStudios.insert(studioId)
            do {
                let rooms = try await firestore.fetchRooms(for: studioId)
                for room in rooms where missingRoomIds.contains(room.id) {
                    roomNames[room.id] = room.name
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func displayName(forUser id: String) -> String {
        if let current = currentUserProvider(), current.id == id {
            return "You"
        }
        return userNames[id] ?? id
    }

    func studioName(for id: String) -> String {
        studioNames[id] ?? id
    }

    func roomName(for id: String) -> String {
        roomNames[id] ?? id
    }

    struct CalendarDaySummary: Identifiable {
        let date: Date
        let bookings: [Booking]

        var id: Date { date }

        var label: String {
            Self.labelFormatter.string(from: date)
        }

        var weekday: String {
            Self.weekdayFormatter.string(from: date)
        }

        private static let labelFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter
        }()

        private static let weekdayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter
        }()
    }
}
