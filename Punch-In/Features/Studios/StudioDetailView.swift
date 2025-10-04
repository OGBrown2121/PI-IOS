import SwiftUI

struct StudioDetailView: View {
    @Environment(\.di) private var di
    @EnvironmentObject private var appState: AppState

    let studio: Studio

    @State private var ownerProfile: UserProfile?
    @State private var isLoadingOwner = false
    @State private var ownerErrorMessage: String?
    @State private var acceptedEngineers: [UserProfile] = []
    @State private var isLoadingEngineers = false
    @State private var engineerErrorMessage: String?
    @State private var currentRequest: StudioEngineerRequest?
    @State private var isProcessingRequest = false
    @State private var isCancellingRequest = false
    @State private var requestErrorMessage: String?
    @State private var observedApprovedEngineerIds: [String]?
    @State private var isBookingPresented = false
    @State private var todaysAvailability: [RoomAvailabilityLine] = []
    @State private var availabilityMessage: String?
    @State private var isLoadingAvailability = false
    @State private var reviews: [Review] = []
    @State private var isLoadingReviews = false
    @State private var reviewsErrorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacingLarge) {
                heroHeader
                quickStatsCard
                todaysHoursCard
                reviewsSection
                if canCurrentUserBook {
                    PrimaryButton(title: "Book this studio") {
                        isBookingPresented = true
                    }
                }
                engineerActionSection
                availableEngineersSection
                amenitiesSection
                detailsSection
            }
            .padding(Theme.spacingLarge)
        }
        .navigationTitle(studio.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadOwnerIfNeeded()
            await loadEngineerRequestIfNeeded()
            updateEngineerStatusCache(with: studio.approvedEngineerIds)
            observedApprovedEngineerIds = studio.approvedEngineerIds
            await loadAcceptedEngineersIfNeeded(force: false)
            await loadTodayAvailability()
            await loadReviews()
        }
        .onChange(of: studio.approvedEngineerIds) { ids in
            updateEngineerStatusCache(with: ids)
            Task { await loadAcceptedEngineersIfNeeded(force: true) }
        }
        .sheet(isPresented: $isBookingPresented) {
            BookingFlowView(
                studio: studio,
                bookingService: di.bookingService,
                firestoreService: di.firestoreService,
                currentUserProvider: { appState.currentUser }
            )
        }
    }

    private var heroHeader: some View {
        VStack(spacing: Theme.spacingLarge) {
            if let coverURL = studio.coverImageURL {
                AsyncImage(url: coverURL) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color(uiColor: .secondarySystemGroupedBackground)
                            ProgressView()
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color(uiColor: .secondarySystemGroupedBackground)
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 200)
                .overlay(alignment: .bottomLeading) {
                    if let logoURL = studio.logoImageURL {
                        AsyncImage(url: logoURL) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                Image(systemName: "music.note.house")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, height: 56)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 64, height: 64)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 3)
                        )
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else if let logoURL = studio.logoImageURL {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        Image(systemName: "music.note.house")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: 160)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                Text(studio.name)
                    .font(.largeTitle.weight(.bold))
                Text(locationText)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if let tagline = ownerProfile?.profileDetails.bio, !tagline.isEmpty {
                    Text(tagline)
                        .font(Theme.bodyFont())
                        .foregroundStyle(.secondary)
                        .padding(.top, Theme.spacingSmall)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var quickStatsCard: some View {
        Group {
            if studio.rooms != nil || formattedHourlyRate != nil {
                HStack(spacing: Theme.spacingLarge) {
                    if let rooms = studio.rooms {
                        StatPill(icon: "square.grid.2x2", title: "Rooms", value: "\(rooms)")
                    }
                    if let rateText = formattedHourlyRate {
                        StatPill(icon: "clock", title: "Rate", value: rateText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var todaysHoursCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Text("Today's Hours")
                    .font(.headline)
            }

            if isLoadingAvailability {
                Text("Checking availability…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let message = availabilityMessage {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if todaysAvailability.isEmpty {
                Text("No rooms configured")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(todaysAvailability) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(line.roomName)
                                .font(.subheadline.weight(.semibold))
                            Text(line.displayText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let timezoneLabel = scheduleTimeZoneAbbreviation {
                Text(timezoneLabel)
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private var canCurrentUserBook: Bool {
        guard let user = appState.currentUser else { return false }
        return user.accountType == .artist
    }

    @ViewBuilder
    private var engineerActionSection: some View {
        if isCurrentUserEngineer {
            VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                switch currentEngineerStatus {
                case .accepted:
                    Label("You're available at this studio", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    withdrawButton(title: "Leave this studio")
                case .pending:
                    HStack(spacing: Theme.spacingSmall) {
                        Image(systemName: "hourglass")
                            .foregroundStyle(.secondary)
                        Text("Your request is pending review")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    withdrawButton(title: "Withdraw request")
                case .denied:
                    Label("Your last request was declined", systemImage: "xmark.seal")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    requestButton(title: "Request again")
                case .none:
                    requestButton(title: "Request to work here")
                }

                if isProcessingRequest || isCancellingRequest {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Theme.primaryColor)
                }

                if let requestErrorMessage {
                    Text(requestErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(Theme.spacingLarge)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.12), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var availableEngineersSection: some View {
        if isLoadingEngineers {
            HStack(spacing: Theme.spacingSmall) {
                ProgressView()
                Text("Loading engineers…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if let engineerErrorMessage {
            Label(engineerErrorMessage, systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if !acceptedEngineers.isEmpty {
            VStack(alignment: .leading, spacing: Theme.spacingMedium) {
                Text("Available Engineers")
                    .font(.headline)

                ForEach(acceptedEngineers) { engineer in
                    NavigationLink {
                        EngineerDetailView(engineerId: engineer.id, profile: engineer)
                    } label: {
                        EngineerRow(profile: engineer)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Label("Reviews", systemImage: "star.circle.fill")
                .font(.headline)

            if isLoadingReviews {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let message = reviewsErrorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if reviews.isEmpty {
                Text("No reviews yet. Be the first to share your experience.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ratingSummary
                Divider()
                let featuredReviews = topReviews
                ForEach(Array(featuredReviews.enumerated()), id: \.element.id) { entry in
                    let review = entry.element
                    let index = entry.offset
                    reviewRow(for: review)
                    if index < featuredReviews.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    private var ratingSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.yellow)
                Text(averageRatingText)
                    .font(.title3.weight(.semibold))
            }

            Text("\(reviews.count) review\(reviews.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var averageRatingText: String {
        guard let averageRating else { return "–" }
        return String(format: "%.1f", averageRating)
    }

    private var averageRating: Double? {
        guard reviews.isEmpty == false else { return nil }
        let total = reviews.reduce(0.0) { $0 + Double($1.rating) }
        return total / Double(reviews.count)
    }

    private var topReviews: [Review] {
        Array(sortedReviews.prefix(3))
    }

    private var sortedReviews: [Review] {
        reviews.sorted { $0.createdAt > $1.createdAt }
    }

    private func reviewRow(for review: Review) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                starRow(rating: review.rating)
                Text(review.reviewerAccountType.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedReviewDate(review.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if review.comment.trimmed.isEmpty == false {
                Text(review.comment)
                    .font(.footnote)
            } else {
                Text("No written feedback provided.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func starRow(rating: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(value <= rating ? Color.yellow : Color.secondary)
            }
        }
    }

    private func formattedReviewDate(_ date: Date) -> String {
        Self.reviewDateFormatter.string(from: date)
    }

    private static let reviewDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private var amenitiesSection: some View {
        Group {
            if !studio.amenities.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacingSmall) {
                    Text("Amenities")
                        .font(.headline)

                    let columns = [GridItem(.adaptive(minimum: 120), spacing: 12)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(studio.amenities, id: \.self) { amenity in
                            Text(amenity)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spacingSmall) {
            Text("Studio Details")
                .font(.headline)

            LabeledContent("Location", value: locationText)

            if !studio.address.isEmpty {
                LabeledContent("Address", value: studio.address)
            }

            if let rooms = studio.rooms {
                LabeledContent("Rooms", value: "\(rooms)")
            }

            if let rateText = formattedHourlyRate {
                LabeledContent("Hourly rate", value: rateText)
            }

            if let profile = ownerProfile {
                if !profile.profileDetails.fieldOne.isEmpty {
                    LabeledContent("Studio name", value: profile.profileDetails.fieldOne)
                }
                if !profile.profileDetails.fieldTwo.isEmpty {
                    LabeledContent("Studio location", value: profile.profileDetails.fieldTwo)
                }
            }

            Divider().padding(.vertical, Theme.spacingMedium)

            Text("Booking")
                .font(.headline)
            Text("Booking through PunchIn is coming soon. In the meantime, reach out to the owner directly to plan your session.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var locationText: String {
        if let location = ownerProfile?.profileDetails.fieldTwo, !location.isEmpty {
            return location
        }
        if !studio.city.trimmed.isEmpty {
            return studio.city
        }
        if !studio.address.trimmed.isEmpty {
            return studio.address.trimmed
        }
        return "Location coming soon"
    }

    private var isCurrentUserEngineer: Bool {
        guard let profile = appState.currentUser else { return false }
        return profile.accountType == .engineer
    }

    private var currentEngineerId: String? {
        guard isCurrentUserEngineer, let id = appState.currentUser?.id else { return nil }
        return id
    }

    private var currentEngineerStatus: StudioEngineerRequest.Status? {
        if let engineerId = currentEngineerId,
           approvedEngineerIds.contains(engineerId) {
            return .accepted
        }
        return currentRequest?.status
    }

    private var formattedHourlyRate: String? {
        guard let rate = studio.hourlyRate else { return nil }
        return rate.formatted(.currency(code: "USD"))
    }

    private func loadOwnerIfNeeded() async {
        guard ownerProfile == nil, !isLoadingOwner else { return }
        isLoadingOwner = true
        ownerErrorMessage = nil

        do {
            ownerProfile = try await di.firestoreService.loadUserProfile(for: studio.ownerId)
        } catch {
            ownerErrorMessage = error.localizedDescription
        }

        isLoadingOwner = false
    }

    private func loadReviews() async {
        guard isLoadingReviews == false else { return }
        isLoadingReviews = true
        reviewsErrorMessage = nil

        do {
            reviews = try await di.reviewService.fetchReviews(for: studio.id, kind: .studio)
        } catch {
            reviewsErrorMessage = error.localizedDescription
        }

        isLoadingReviews = false
    }

    private func loadEngineerRequestIfNeeded() async {
        guard currentRequest == nil, let engineerId = currentEngineerId else { return }
        do {
            let request = try await di.firestoreService.fetchEngineerRequest(studioId: studio.id, engineerId: engineerId)
            currentRequest = request
        } catch {
            requestErrorMessage = error.localizedDescription
        }
    }

    private func loadAcceptedEngineersIfNeeded(force: Bool) async {
        let targetIDs = studio.approvedEngineerIds

        if targetIDs.isEmpty {
            acceptedEngineers = []
            engineerErrorMessage = nil
            observedApprovedEngineerIds = targetIDs
            return
        }

        if !force {
            let loadedIDs = acceptedEngineers.map(\.id)
            if loadedIDs == targetIDs {
                return
            }
        }

        isLoadingEngineers = true
        engineerErrorMessage = nil

        do {
            let profiles = try await di.firestoreService.fetchUserProfiles(for: targetIDs)
            acceptedEngineers = profiles
            observedApprovedEngineerIds = targetIDs
        } catch {
            engineerErrorMessage = error.localizedDescription
            acceptedEngineers = []
        }

        isLoadingEngineers = false
    }

    private func submitEngineerRequest() async {
        guard let engineerId = currentEngineerId else { return }
        guard currentEngineerStatus != .accepted else { return }

        isProcessingRequest = true
        requestErrorMessage = nil

        do {
            try await di.firestoreService.submitEngineerRequest(
                studioId: studio.id,
                studioOwnerId: studio.ownerId,
                engineerId: engineerId
            )
            currentRequest = try await di.firestoreService.fetchEngineerRequest(studioId: studio.id, engineerId: engineerId)
        } catch {
            requestErrorMessage = error.localizedDescription
        }

        isProcessingRequest = false
    }

    private func withdrawEngineerRequest() async {
        guard let engineerId = currentEngineerId else { return }
        isCancellingRequest = true
        requestErrorMessage = nil

        do {
            try await di.firestoreService.withdrawEngineerRequest(studioId: studio.id, engineerId: engineerId)
            currentRequest = nil
            acceptedEngineers.removeAll { $0.id == engineerId }
            let updatedIds = approvedEngineerIds.filter { $0 != engineerId }
            observedApprovedEngineerIds = updatedIds
            updateEngineerStatusCache(with: updatedIds)
            await loadAcceptedEngineersIfNeeded(force: true)
        } catch {
            requestErrorMessage = error.localizedDescription
        }

        isCancellingRequest = false
    }

    private func updateEngineerStatusCache(with ids: [String]) {
        guard let engineerId = currentEngineerId else { return }
        if ids.contains(engineerId) {
            if var request = currentRequest {
                request.status = .accepted
                request.updatedAt = Date()
                currentRequest = request
            } else {
                currentRequest = StudioEngineerRequest(
                    id: engineerId,
                    studioId: studio.id,
                    engineerId: engineerId,
                    studioOwnerId: studio.ownerId,
                    status: .accepted,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        } else if currentRequest?.status == .accepted {
            currentRequest = nil
        }
    }

    private var approvedEngineerIds: [String] {
        observedApprovedEngineerIds ?? studio.approvedEngineerIds
    }

    @ViewBuilder
    private func requestButton(title: String) -> some View {
        Button {
            Task { await submitEngineerRequest() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Theme.primaryGradientStart, Theme.primaryGradientEnd],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProcessingRequest || isCancellingRequest)
    }

    @ViewBuilder
    private func withdrawButton(title: String) -> some View {
        Button {
            Task { await withdrawEngineerRequest() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "xmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.primaryColor)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.primaryColor.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isProcessingRequest || isCancellingRequest)
    }
}

private extension StudioDetailView {
    var scheduleTimeZoneAbbreviation: String? {
        let identifier = studio.operatingSchedule.timeZoneIdentifier
        guard let timezone = TimeZone(identifier: identifier) else { return nil }
        return timezone.abbreviation()
    }

    @MainActor
    func loadTodayAvailability() async {
        guard isLoadingAvailability == false else { return }
        isLoadingAvailability = true
        availabilityMessage = nil
        todaysAvailability = []
        defer { isLoadingAvailability = false }

        do {
            async let roomsTask = di.firestoreService.fetchRooms(for: studio.id)
            async let bookingsTask = di.bookingService.fetchBookings(for: studio.id, role: .studio)
            let rooms = try await roomsTask
            let bookings = try await bookingsTask
            if rooms.isEmpty {
                availabilityMessage = "No rooms configured"
                todaysAvailability = []
                return
            }
            let availability = computeAvailability(for: rooms, bookings: bookings)
            todaysAvailability = availability
            availabilityMessage = availability.isEmpty ? "No open times today" : nil
        } catch {
            availabilityMessage = error.localizedDescription
        }
    }

    func computeAvailability(for rooms: [Room], bookings: [Booking]) -> [RoomAvailabilityLine] {
        let timezone = TimeZone(identifier: studio.operatingSchedule.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        let todayStart = calendar.startOfDay(for: Date())
        guard let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return [] }

        if studio.operatingSchedule.blackoutDates.contains(where: { calendar.isDate($0, inSameDayAs: todayStart) }) {
            return rooms.sorted { $0.name < $1.name }.map { room in
                RoomAvailabilityLine(id: room.id, roomName: room.name, displayText: "Closed today")
            }
        }

        let baseWindows = baseOpenWindows(for: todayStart, endOfDay: todayEnd, calendar: calendar)
        guard baseWindows.isEmpty == false else {
            return rooms.sorted { $0.name < $1.name }.map { room in
                RoomAvailabilityLine(id: room.id, roomName: room.name, displayText: "Closed today")
            }
        }

        let relevantStatuses: Set<BookingStatus> = [.pending, .confirmed, .rescheduled]
        let bookingsByRoom = Dictionary(grouping: bookings.filter { relevantStatuses.contains($0.status) }) { $0.roomId }

        let formatter = timeFormatter(for: timezone)

        return rooms.sorted { $0.name < $1.name }.map { room in
            var openSegments = baseWindows
            let roomBookings = bookingsByRoom[room.id] ?? []

            for booking in roomBookings {
                guard let interval = clampedInterval(for: booking, dayStart: todayStart, dayEnd: todayEnd) else { continue }
                openSegments = subtract(openSegments, removing: interval)
            }

            let labels = openSegments
                .sorted { $0.start < $1.start }
                .map { format(interval: $0, formatter: formatter, dayEnd: todayEnd, calendar: calendar) }
                .filter { !$0.isEmpty }

            let text = labels.isEmpty ? "Fully booked today" : labels.joined(separator: " • ")
            return RoomAvailabilityLine(id: room.id, roomName: room.name, displayText: text)
        }
    }

    func baseOpenWindows(for dayStart: Date, endOfDay: Date, calendar: Calendar) -> [DateInterval] {
        let schedule = studio.operatingSchedule
        if schedule.recurringHours.isEmpty {
            return [DateInterval(start: dayStart, end: endOfDay)]
        }

        let weekdayComponent = calendar.component(.weekday, from: dayStart)
        let normalizedWeekday = (weekdayComponent + 6) % 7

        let windows = schedule.recurringHours
            .filter { $0.weekday == normalizedWeekday }
            .sorted { $0.startTimeMinutes < $1.startTimeMinutes }

        return windows.compactMap { window in
            guard let start = calendar.date(byAdding: .minute, value: window.startTimeMinutes, to: dayStart) else { return nil }
            let end = min(start.addingTimeInterval(TimeInterval(window.durationMinutes * 60)), endOfDay)
            guard start < end else { return nil }
            return DateInterval(start: start, end: end)
        }
    }

    func clampedInterval(for booking: Booking, dayStart: Date, dayEnd: Date) -> DateInterval? {
        let start = booking.confirmedStart ?? booking.requestedStart
        let end = booking.confirmedEnd ?? booking.requestedEnd
        let clampedStart = max(start, dayStart)
        let clampedEnd = min(end, dayEnd)
        guard clampedStart < clampedEnd else { return nil }
        return DateInterval(start: clampedStart, end: clampedEnd)
    }

    func subtract(_ intervals: [DateInterval], removing removal: DateInterval) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals {
            guard interval.intersects(removal) else {
                result.append(interval)
                continue
            }

            let overlapStart = max(interval.start, removal.start)
            let overlapEnd = min(interval.end, removal.end)
            guard overlapStart < overlapEnd else {
                result.append(interval)
                continue
            }

            if interval.start < overlapStart {
                result.append(DateInterval(start: interval.start, end: overlapStart))
            }

            if overlapEnd < interval.end {
                result.append(DateInterval(start: overlapEnd, end: interval.end))
            }
        }
        return result
    }

    func format(interval: DateInterval, formatter: DateFormatter, dayEnd: Date, calendar: Calendar) -> String {
        let startString = formatter.string(from: interval.start)
        let adjustedEnd: Date
        if interval.end >= dayEnd {
            adjustedEnd = calendar.date(byAdding: .minute, value: -1, to: dayEnd) ?? interval.end
        } else {
            adjustedEnd = interval.end
        }
        let endString = formatter.string(from: adjustedEnd)
        return "\(startString) – \(endString)"
    }

    func timeFormatter(for timezone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = timezone
        return formatter
    }
}

private struct RoomAvailabilityLine: Identifiable {
    let id: String
    let roomName: String
    let displayText: String
}

private struct EngineerRow: View {
    let profile: UserProfile

    private var displayName: String {
        profile.displayName.isEmpty ? profile.username : profile.displayName
    }

    private var subtitle: String {
        if !profile.profileDetails.fieldOne.isEmpty {
            return profile.profileDetails.fieldOne
        }
        if !profile.profileDetails.fieldTwo.isEmpty {
            return profile.profileDetails.fieldTwo
        }
        return profile.profileDetails.bio
    }

    var body: some View {
        HStack(spacing: Theme.spacingMedium) {
            avatar

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.spacingMedium)
        .padding(.horizontal, Theme.spacingLarge)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.elevatedCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Theme.primaryColor.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let imageURL = profile.profileImageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 54, height: 54)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                case .failure:
                    initialsView
                @unknown default:
                    initialsView
                }
            }
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        let initials = displayName.split(separator: " ")
            .prefix(2)
            .map { $0.first.map(String.init) ?? "" }
            .joined()

        return Circle()
            .fill(Theme.primaryColor.opacity(0.15))
            .frame(width: 54, height: 54)
            .overlay(
                Text(initials.isEmpty ? String(displayName.prefix(2)) : initials)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(Theme.primaryColor)
            )
    }
}

private struct StatPill: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StudioDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            StudioDetailView(studio: .mock())
                .environment(\.di, DIContainer.makeMock())
                .environmentObject(previewAppState)
        }
    }

    private static var previewAppState: AppState {
        let state = AppState()
        state.currentUser = .mockEngineer
        state.isAuthenticated = true
        state.hasCompletedOnboarding = true
        return state
    }
}
