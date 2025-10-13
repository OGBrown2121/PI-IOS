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
        case schedule

        var id: String { rawValue }

        var title: String {
            switch self {
            case .list:
                return "List"
            case .calendar:
                return "Calendar"
            case .schedule:
                return "Schedule"
            }
        }
    }

    @Published private(set) var viewerRole: ViewerRole = .unknown
    @Published private(set) var pendingApprovals: [Booking] = []
    @Published private(set) var scheduledBookings: [Booking] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var displayMode: DisplayMode = .list
    @Published var hideCancelled = false
    @Published var selectedCalendarDate: Date {
        didSet {
            let normalized = calendar.startOfDay(for: selectedCalendarDate)
            if selectedCalendarDate != normalized {
                selectedCalendarDate = normalized
            }
        }
    }
    @Published private(set) var calendarBookings: [Booking] = []
    @Published private(set) var pastBookings: [Booking] = []
    @Published private(set) var pendingReviews: [ReviewTask] = []
    @Published private var actionInFlight: Set<String> = []
    @Published private var reviewActionInFlight: Set<String> = []
    @Published private var userNames: [String: String] = [:]
    @Published private var studioNames: [String: String] = [:]
    @Published private var studioDetails: [String: Studio] = [:]
    @Published private var roomNames: [String: String] = [:]
    @Published private var userProfiles: [String: UserProfile] = [:]
    @Published private(set) var engineerProfiles: [String: UserProfile] = [:]

    private let bookingService: any BookingService
    private let firestore: any FirestoreService
    private let reviewService: any ReviewService
    private let currentUserProvider: () -> UserProfile?
    private let calendar: Calendar
    private let rescheduleDurationOptions: [Int] = [30, 60, 90, 120, 180, 240]
    private var ownedStudioEngineerIds: Set<String> = []
    private var ownedStudioIds: Set<String> = []
    private var authoredReviews: [String: Review] = [:]
    private var cachedBookings: [Booking] = []
    private var dismissedReviewTaskIds: Set<String>
    private static let dismissedReviewStorageKey = "booking_review_dismissed_ids"

    init(
        bookingService: any BookingService,
        firestoreService: any FirestoreService,
        reviewService: any ReviewService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.bookingService = bookingService
        self.firestore = firestoreService
        self.reviewService = reviewService
        self.currentUserProvider = currentUserProvider
        let calendar = Calendar.current
        self.calendar = calendar
        self.selectedCalendarDate = calendar.startOfDay(for: Date())
        if let stored = UserDefaults.standard.array(forKey: Self.dismissedReviewStorageKey) as? [String] {
            dismissedReviewTaskIds = Set(stored)
        } else {
            dismissedReviewTaskIds = []
        }
    }

    func load() async {
        guard isLoading == false else { return }
        await refresh()
    }

    func booking(withId id: String) -> Booking? {
        if let match = cachedBookings.first(where: { $0.id == id }) {
            return match
        }
        if let match = pendingApprovals.first(where: { $0.id == id }) {
            return match
        }
        if let match = scheduledBookings.first(where: { $0.id == id }) {
            return match
        }
        if let match = pastBookings.first(where: { $0.id == id }) {
            return match
        }
        return nil
    }

    func reloadBookingIfNeeded(withId id: String) async -> Booking? {
        if let existing = booking(withId: id) {
            return existing
        }
        await refresh()
        return booking(withId: id)
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
            pastBookings = []
            pendingReviews = []
            cachedBookings = []
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
            pastBookings = []
            engineerProfiles = [:]
            pendingReviews = []
            cachedBookings = []
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

    func canCancel(_ booking: Booking) -> Bool {
        guard let user = currentUserProvider() else { return false }
        switch viewerRole {
        case .artist:
            return booking.artistId == user.id && booking.status != .cancelled && booking.status != .completed
        case .engineer:
            return booking.engineerId == user.id && booking.status != .cancelled && booking.status != .completed
        case .studioOwner:
            return booking.status != .cancelled && booking.status != .completed
        default:
            return false
        }
    }

    func canReschedule(_ booking: Booking) -> Bool {
        guard let user = currentUserProvider() else { return false }
        switch viewerRole {
        case .artist:
            return booking.artistId == user.id && booking.status != .cancelled && booking.status != .completed
        case .engineer:
            return booking.engineerId == user.id && booking.status != .cancelled && booking.status != .completed
        case .studioOwner:
            return booking.status != .cancelled && booking.status != .completed
        default:
            return false
        }
    }

    func canComplete(_ booking: Booking) -> Bool {
        guard booking.status != .cancelled && booking.status != .completed else { return false }
        guard let user = currentUserProvider() else { return false }
        let now = Date()
        guard booking.requestedEnd <= now else { return false }

        switch viewerRole {
        case .engineer:
            return booking.engineerId == user.id
        case .studioOwner:
            return ownedStudioIds.contains(booking.studioId)
        default:
            return false
        }
    }

    func cancel(_ booking: Booking) async {
        guard canCancel(booking) else { return }
        await performMutation(on: booking) { booking in
            var updated = booking
            var approval = updated.approval
            approval.requiresEngineerApproval = false
            approval.requiresStudioApproval = false
            if let user = self.currentUserProvider() {
                approval.resolvedBy = user.id
                approval.resolvedAt = Date()
            }
            updated.approval = approval
            updated.status = .cancelled
            updated.confirmedStart = nil
            updated.confirmedEnd = nil
            updated.updatedAt = Date()
            return updated
        }
    }

    func reschedule(_ booking: Booking, to newStart: Date, durationMinutes: Int) async {
        guard canReschedule(booking) else { return }
        do {
            try await bookingService.validateReschedule(for: booking, newStart: newStart, durationMinutes: durationMinutes)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        await performMutation(on: booking) { booking in
            var updated = booking
            let clampedDuration = durationMinutes
            updated.requestedStart = newStart
            updated.requestedEnd = newStart.addingTimeInterval(TimeInterval(clampedDuration * 60))
            updated.durationMinutes = clampedDuration
            updated.status = .pending
            updated.confirmedStart = nil
            updated.confirmedEnd = nil
            var approval = updated.approval
            approval.resolvedBy = nil
            approval.resolvedAt = nil
            switch self.viewerRole {
            case .studioOwner:
                approval.requiresStudioApproval = false
                approval.requiresEngineerApproval = true
            case .engineer:
                approval.requiresStudioApproval = booking.approval.requiresStudioApproval
                approval.requiresEngineerApproval = false
            case .artist:
                approval.requiresEngineerApproval = true
                approval.requiresStudioApproval = booking.approval.requiresStudioApproval
            default:
                break
            }
            updated.approval = approval
            updated.updatedAt = Date()
            return updated
        }
    }

    func complete(_ booking: Booking) async {
        guard canComplete(booking) else { return }
        await performMutation(on: booking) { booking in
            var updated = booking
            var approval = updated.approval
            approval.requiresEngineerApproval = false
            approval.requiresStudioApproval = false
            if let user = self.currentUserProvider() {
                approval.resolvedBy = user.id
                approval.resolvedAt = Date()
            }
            updated.approval = approval
            updated.status = .completed
            if updated.confirmedStart == nil {
                updated.confirmedStart = updated.requestedStart
            }
            if updated.confirmedEnd == nil {
                updated.confirmedEnd = updated.requestedEnd
            }
            updated.updatedAt = Date()
            return updated
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
            ownedStudioIds = []
            let bookings = try await bookingService.fetchBookings(for: user.id, role: .engineer)
            let sorted = bookings.sorted { $0.requestedStart < $1.requestedStart }
            let now = Date()
            let pending = sorted.filter { booking in
                booking.status == .pending && booking.approval.requiresEngineerApproval
            }
            let pendingIds = Set(pending.map { $0.id })
            let upcoming = sorted.filter { booking in
                booking.status != .cancelled
                    && booking.requestedEnd > now
                    && pendingIds.contains(booking.id) == false
            }
            let historical = sorted.filter { isPastBooking($0, relativeTo: now) }
            let calendarEligible = sorted.filter { isPastBooking($0, relativeTo: now) == false }
            cachedBookings = sorted
            await resolveMetadata(for: sorted)
            updateCalendarData(with: calendarEligible)
            pendingApprovals = pending
            scheduledBookings = upcoming
            pastBookings = historical
            await rebuildPendingReviews(with: sorted, for: user, role: .engineer)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingApprovals = []
            scheduledBookings = []
            pastBookings = []
            pendingReviews = []
            cachedBookings = []
        }
    }

    private func loadArtistBookings(for user: UserProfile) async {
        do {
            ownedStudioIds = []
            let bookings = try await bookingService.fetchBookings(for: user.id, role: .artist)
            let sorted = bookings.sorted { $0.requestedStart < $1.requestedStart }
            let now = Date()
            let historical = sorted.filter { isPastBooking($0, relativeTo: now) }
            let upcoming = sorted.filter { isPastBooking($0, relativeTo: now) == false && $0.status != .cancelled }
            let calendarEligible = sorted.filter { isPastBooking($0, relativeTo: now) == false }
            cachedBookings = sorted
            scheduledBookings = upcoming
            await resolveMetadata(for: sorted)
            updateCalendarData(with: calendarEligible)
            pastBookings = historical
            pendingApprovals = []
            await rebuildPendingReviews(with: sorted, for: user, role: .artist)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            scheduledBookings = []
            pendingApprovals = []
            pastBookings = []
            pendingReviews = []
            cachedBookings = []
        }
    }

    private func loadStudioBookings(for user: UserProfile) async {
        do {
            let studios = try await firestore.fetchStudios()
            let ownedStudios = studios.filter { $0.ownerId == user.id }
            ownedStudioIds = Set(ownedStudios.map { $0.id })
            #if DEBUG
            print("[BookingInbox] studio owner=\(user.id) owns: \(ownedStudios.map { $0.id }))")
            #endif

            guard ownedStudios.isEmpty == false else {
                ownedStudioIds = []
                pendingApprovals = []
                scheduledBookings = []
                pastBookings = []
                errorMessage = "Add a studio to receive booking requests."
                updateCalendarData(with: [])
                return
            }

            var allBookings: [Booking] = []
            ownedStudioEngineerIds = []
            for studio in ownedStudios {
                studioNames[studio.id] = studio.name
                studioDetails[studio.id] = studio
                let bookings = try await bookingService.fetchBookings(for: studio.id, role: .studio)
                allBookings.append(contentsOf: bookings)
                ownedStudioEngineerIds.formUnion(studio.approvedEngineerIds)
            }

            let sorted = allBookings.sorted { $0.requestedStart < $1.requestedStart }
            let pending = sorted.filter { $0.status == .pending && $0.approval.requiresStudioApproval }
            let pendingIds = Set(pending.map { $0.id })
            let now = Date()
            let upcoming = sorted.filter { booking in
                booking.status != .cancelled
                    && booking.requestedEnd > now
                    && pendingIds.contains(booking.id) == false
            }
            let historical = sorted.filter { isPastBooking($0, relativeTo: now) }
            let calendarEligible = sorted.filter { isPastBooking($0, relativeTo: now) == false }

            cachedBookings = sorted
            await resolveMetadata(for: sorted, ownedStudios: ownedStudios)
            await loadEngineerProfilesIfNeeded(for: ownedStudios)
            updateCalendarData(with: calendarEligible)

            pendingApprovals = pending
            scheduledBookings = upcoming
            pastBookings = historical
            await rebuildPendingReviews(with: sorted, for: user, role: .studioOwner)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            pendingApprovals = []
            scheduledBookings = []
            pastBookings = []
            pendingReviews = []
            cachedBookings = []
        }
    }

    private func role(for accountType: AccountType) -> ViewerRole {
        if accountType.isEngineer {
            return .engineer
        }
        if accountType.isStudioOwner {
            return .studioOwner
        }
        if accountType.canInitiateBookings {
            return .artist
        }
        return .unsupported
    }

    private func isPastBooking(_ booking: Booking, relativeTo referenceDate: Date) -> Bool {
        if booking.status == .completed || booking.status == .cancelled {
            return true
        }
        return booking.requestedEnd < referenceDate
    }

    func bookings(for date: Date) -> [Booking] {
        let day = calendar.startOfDay(for: date)
        return calendarBookings
            .filter { booking in
                guard calendar.isDate(booking.requestedStart, inSameDayAs: day) else { return false }
                if hideCancelled && booking.status == .cancelled { return false }
                return true
            }
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
            studioDetails[studio.id] = studio
        }

        let userIds = Set(bookings.flatMap { [$0.artistId, $0.engineerId] })
        let missingUserIds = userIds.filter { userNames[$0] == nil }
        if missingUserIds.isEmpty == false {
            do {
                let profiles = try await firestore.fetchUserProfiles(for: Array(missingUserIds))
                for profile in profiles {
                    let name = profile.displayName.isEmpty ? profile.username : profile.displayName
                    userNames[profile.id] = name
                    userProfiles[profile.id] = profile
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
                    studioDetails[studio.id] = studio
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        let missingRoomsByStudio = Dictionary(grouping: bookings.filter { roomNames[$0.roomId] == nil }) { $0.studioId }

        for (studioId, _) in missingRoomsByStudio {
            do {
                let rooms = try await firestore.fetchRooms(for: studioId)
                for room in rooms {
                    roomNames[room.id] = room.name
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rebuildPendingReviews(with bookings: [Booking], for user: UserProfile, role: ViewerRole) async {
        guard bookings.contains(where: { $0.status == .completed }) else {
            pendingReviews = []
            return
        }

        await loadAuthoredReviews(for: user)
        pendingReviews = buildReviewTasks(from: bookings, role: role)
    }

    private func loadAuthoredReviews(for user: UserProfile) async {
        do {
            let reviews = try await reviewService.fetchReviewsAuthored(by: user.id)
            authoredReviews = Dictionary(uniqueKeysWithValues: reviews.map { review in
                (reviewKey(bookingId: review.bookingId, revieweeId: review.revieweeId, kind: review.revieweeKind), review)
            })
        } catch {
            #if DEBUG
            print("[BookingInbox] failed to fetch reviews for user=\(user.id) error=\(error)")
            #endif
            errorMessage = error.localizedDescription
        }
    }

    private func buildReviewTasks(from bookings: [Booking], role: ViewerRole) -> [ReviewTask] {
        guard bookings.isEmpty == false else { return [] }

        var tasks: [ReviewTask] = []

        for booking in bookings where booking.status == .completed {
            let pendingTargets = pendingReviewTargets(for: booking, role: role)
            if pendingTargets.isEmpty == false {
                tasks.append(ReviewTask(
                    id: "\(booking.id)|reviews",
                    booking: booking,
                    targets: pendingTargets,
                    sessionDate: sessionDate(for: booking)
                ))
            }
        }

        let activeIds = Set(tasks.map { $0.id })
        let prunedDismissed = dismissedReviewTaskIds.intersection(activeIds)
        if prunedDismissed != dismissedReviewTaskIds {
            dismissedReviewTaskIds = prunedDismissed
            persistDismissedReviewTasks()
        }

        return tasks
            .filter { dismissedReviewTaskIds.contains($0.id) == false }
            .sorted { $0.sessionDate > $1.sessionDate }
    }

    private func reviewKey(bookingId: String, revieweeId: String, kind: ReviewSubjectKind) -> String {
        "\(bookingId)|\(revieweeId)|\(kind.rawValue)"
    }

    private func sessionDate(for booking: Booking) -> Date {
        booking.confirmedEnd ?? booking.requestedEnd
    }

    private func pendingReviewTargets(for booking: Booking, role: ViewerRole) -> [ReviewTarget] {
        var targets: [ReviewTarget] = []

        switch role {
        case .artist:
            if booking.studioId.isEmpty == false {
                let key = reviewKey(bookingId: booking.id, revieweeId: booking.studioId, kind: .studio)
                if authoredReviews[key] == nil {
                    targets.append(ReviewTarget(revieweeId: booking.studioId, revieweeKind: .studio))
                }
            }

            if booking.engineerId.isEmpty == false {
                let key = reviewKey(bookingId: booking.id, revieweeId: booking.engineerId, kind: .engineer)
                if authoredReviews[key] == nil {
                    targets.append(ReviewTarget(revieweeId: booking.engineerId, revieweeKind: .engineer))
                }
            }
        case .engineer, .studioOwner:
            let key = reviewKey(bookingId: booking.id, revieweeId: booking.artistId, kind: .artist)
            if authoredReviews[key] == nil {
                targets.append(ReviewTarget(revieweeId: booking.artistId, revieweeKind: .artist))
            }
        case .unsupported, .unknown:
            break
        }

        return targets
    }

    func revieweeName(for target: ReviewTarget) -> String {
        switch target.revieweeKind {
        case .studio:
            return studioName(for: target.revieweeId)
        case .artist, .engineer, .studioOwner:
            return displayName(forUser: target.revieweeId)
        }
    }

    func reviewTitle(for task: ReviewTask) -> String {
        if task.targets.count > 1 {
            return "Review this session"
        }
        if let target = task.targets.first {
            switch target.revieweeKind {
            case .studio:
                return "Review \(revieweeName(for: target))"
            case .engineer:
                return "Rate \(revieweeName(for: target))"
            case .artist:
                return "Share feedback for \(revieweeName(for: target))"
            case .studioOwner:
                return "Review \(revieweeName(for: target))"
            }
        }
        return "Leave a review"
    }

    func reviewSubtitle(for task: ReviewTask) -> String {
        "Session completed on \(Self.reviewSessionFormatter.string(from: task.sessionDate))"
    }

    func reviewPrompt(for target: ReviewTarget) -> String {
        switch target.revieweeKind {
        case .studio:
            return "How was the studio experience?"
        case .engineer:
            return "How did the engineer support your session?"
        case .artist:
            return "How was collaborating with this artist?"
        case .studioOwner:
            return "Share feedback about the studio owner."
        }
    }

    func isSubmittingReview(for task: ReviewTask) -> Bool {
        reviewActionInFlight.contains(task.id)
    }

    func submitReviews(task: ReviewTask, responses: [ReviewTarget: ReviewResponse]) async {
        guard let user = currentUserProvider() else { return }
        guard reviewActionInFlight.contains(task.id) == false else { return }

        reviewActionInFlight.insert(task.id)
        defer { reviewActionInFlight.remove(task.id) }

        do {
            for target in task.targets {
                guard let response = responses[target], (1...5).contains(response.rating) else { continue }
                let trimmedComment = response.comment.trimmingCharacters(in: .whitespacesAndNewlines)
                var review = Review(
                    bookingId: task.booking.id,
                    reviewerId: user.id,
                    reviewerAccountType: user.accountType,
                    revieweeId: target.revieweeId,
                    revieweeKind: target.revieweeKind,
                    rating: response.rating,
                    comment: trimmedComment
                )
                try await reviewService.submitReview(review)
                review = review.updating(rating: response.rating, comment: trimmedComment)
                let key = reviewKey(bookingId: review.bookingId, revieweeId: review.revieweeId, kind: review.revieweeKind)
                authoredReviews[key] = review
            }
            pendingReviews.removeAll { $0.id == task.id }
            dismissedReviewTaskIds.remove(task.id)
            persistDismissedReviewTasks()
            pendingReviews = buildReviewTasks(from: cachedBookings, role: viewerRole)
        } catch {
            #if DEBUG
            print("[BookingInbox] failed to submit review task=\(task.id) error=\(error)")
            #endif
            self.errorMessage = error.localizedDescription
        }
    }

    func hideReviewReminder(for task: ReviewTask) {
        dismissedReviewTaskIds.insert(task.id)
        persistDismissedReviewTasks()
        pendingReviews.removeAll { $0.id == task.id }
    }

    struct ReviewResponse {
        let rating: Int
        let comment: String
    }

    private func persistDismissedReviewTasks() {
        UserDefaults.standard.set(Array(dismissedReviewTaskIds), forKey: Self.dismissedReviewStorageKey)
    }

    private static let reviewSessionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    func displayName(forUser id: String) -> String {
        if let current = currentUserProvider(), current.id == id {
            return "You"
        }
        return userNames[id] ?? userProfiles[id]?.displayName ?? id
    }

    func studioName(for id: String) -> String {
        studioNames[id] ?? id
    }

    func studio(for id: String) -> Studio? {
        studioDetails[id]
    }

    func roomName(for id: String) -> String {
        roomNames[id] ?? id
    }

    func userProfile(for id: String) -> UserProfile? {
        if let profile = userProfiles[id] {
            return profile
        }
        if let current = currentUserProvider(), current.id == id {
            return current
        }
        return nil
    }

    func durationOptions(including value: Int) -> [Int] {
        var options = Set(rescheduleDurationOptions)
        options.insert(value)
        return options.sorted()
    }

    var availableDisplayModes: [DisplayMode] {
        switch viewerRole {
        case .studioOwner:
            return [.list, .calendar, .schedule]
        default:
            return [.list, .calendar]
        }
    }

    var engineerSchedulesForSelectedDate: [EngineerSchedule] {
        guard viewerRole == .studioOwner else { return [] }
        let dayStart = calendar.startOfDay(for: selectedCalendarDate)
        return ownedStudioEngineerIds
            .sorted { displayName(forUser: $0) < displayName(forUser: $1) }
            .map { id in
        let bookings = calendarBookings
            .filter {
                guard $0.engineerId == id else { return false }
                guard $0.status != .completed else { return false }
                if hideCancelled && $0.status == .cancelled { return false }
                return calendar.isDate($0.requestedStart, inSameDayAs: dayStart)
            }
            .sorted { $0.requestedStart < $1.requestedStart }
                let profile = engineerProfiles[id] ?? userProfiles[id]
                return EngineerSchedule(engineerId: id, profile: profile, bookings: bookings)
            }
    }

    func label(for booking: Booking) -> String {
        let formatter = Self.timeRangeFormatter
        let start = booking.requestedStart
        let end = booking.requestedEnd
        return formatter.string(from: start) + " – " + formatter.string(from: end)
    }

    func attachConversation(_ conversationId: String, to booking: Booking) async {
        guard booking.conversationId != conversationId else { return }

        var updated = booking
        updated.conversationId = conversationId
        updated.updatedAt = Date()

        do {
            try await bookingService.updateBooking(updated)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    struct EngineerSchedule: Identifiable {
        let engineerId: String
        let profile: UserProfile?
        let bookings: [Booking]

        var id: String { engineerId }
    }

    struct ReviewTarget: Identifiable, Equatable, Hashable {
        let revieweeId: String
        let revieweeKind: ReviewSubjectKind

        var id: String { "\(revieweeKind.rawValue)|\(revieweeId)" }
    }

    struct ReviewTask: Identifiable, Equatable {
        let id: String
        let booking: Booking
        let targets: [ReviewTarget]
        let sessionDate: Date
    }

    private static let timeRangeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private func loadEngineerProfilesIfNeeded(for studios: [Studio]) async {
        let engineerIds = Set(studios.flatMap { $0.approvedEngineerIds })
        let missingIds = engineerIds.filter { engineerProfiles[$0] == nil && userProfiles[$0] == nil }
        guard missingIds.isEmpty == false else { return }
        do {
            let profiles = try await firestore.fetchUserProfiles(for: Array(missingIds))
            for profile in profiles {
                engineerProfiles[profile.id] = profile
                userProfiles[profile.id] = profile
                userNames[profile.id] = profile.displayName.isEmpty ? profile.username : profile.displayName
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
