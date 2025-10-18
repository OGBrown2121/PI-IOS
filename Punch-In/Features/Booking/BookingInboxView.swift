import SwiftUI

struct BookingInboxView: View {
    @StateObject private var viewModel: BookingInboxViewModel
    @State private var isShowingAlerts = false

    init(
        bookingService: any BookingService,
        firestoreService: any FirestoreService,
        reviewService: any ReviewService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        _viewModel = StateObject(
            wrappedValue: BookingInboxViewModel(
                bookingService: bookingService,
                firestoreService: firestoreService,
                reviewService: reviewService,
                currentUserProvider: currentUserProvider
            )
        )
    }

    var body: some View {
        content
            .background(Theme.appBackground.ignoresSafeArea())
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AlertsButton { isShowingAlerts = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ChatPillButton()
                }
            }
            .sheet(isPresented: $isShowingAlerts) {
                NavigationStack {
                    AlertsView()
                }
            }
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewerRole {
        case .unknown:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.appBackground)
        case .unsupported:
            ContentUnavailableView(
                "Bookings unavailable",
                systemImage: "calendar.badge.xmark",
                description: Text("Sign in to a supported account to manage bookings.")
            )
        case .artist:
            InboxContent(
                pending: [],
                scheduled: viewModel.scheduledBookings,
                title: "Your Sessions",
                subtitle: "Upcoming bookings",
                allowPendingActions: false
            )
            .environmentObject(viewModel)
        case .studioOwner:
            InboxContent(
                pending: viewModel.pendingApprovals,
                scheduled: viewModel.scheduledBookings,
                title: "Needs your approval",
                subtitle: "Sessions at your studios",
                allowPendingActions: true
            )
            .environmentObject(viewModel)
        case .engineer:
            InboxContent(
                pending: viewModel.pendingApprovals,
                scheduled: viewModel.scheduledBookings,
                title: "Pending approvals",
                subtitle: "Sessions you’re part of",
                allowPendingActions: true
            )
            .environmentObject(viewModel)
        }
    }
}

private struct InboxContent: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel
    @EnvironmentObject private var appState: AppState

    let pending: [Booking]
    let scheduled: [Booking]
    let title: String
    let subtitle: String
    let allowPendingActions: Bool

    @State private var bookingToReschedule: Booking?
    @State private var bookingToCancel: Booking?
    @State private var showCancelDialog = false
    @State private var reviewTask: BookingInboxViewModel.ReviewTask?
    @State private var bookingForDetails: Booking?
    @State private var showHistorySheet = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("Display Mode", selection: $viewModel.displayMode) {
                ForEach(viewModel.availableDisplayModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top)

            if viewModel.pastBookings.isEmpty == false {
                historyButton
            }

            if viewModel.pendingReviews.isEmpty == false {
                PendingReviewsSection(
                    tasks: viewModel.pendingReviews,
                    onSelect: { task in reviewTask = task },
                    onHide: { task in viewModel.hideReviewReminder(for: task) }
                )
            }

            switch viewModel.displayMode {
            case .list:
                BookingListView(
                    pending: pending,
                    scheduled: scheduled,
                    title: title,
                    subtitle: subtitle,
                    allowPendingActions: allowPendingActions,
                    onReschedule: { bookingToReschedule = $0 },
                    onCancel: { booking in
                        bookingToCancel = booking
                        showCancelDialog = true
                    },
                    onSelect: { bookingForDetails = $0 }
                )
            case .schedule:
                EngineerScheduleView()
            case .openTimes:
                EngineerOpenTimesView()
            case .calendar:
                BookingCalendarView(
                    allowPendingActions: allowPendingActions,
                    onReschedule: { bookingToReschedule = $0 },
                    onCancel: { booking in
                        bookingToCancel = booking
                        showCancelDialog = true
                    },
                    onSelect: { bookingForDetails = $0 }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $bookingToReschedule) { booking in
            RescheduleBookingSheet(
                booking: booking,
                durationOptions: viewModel.durationOptions(including: booking.durationMinutes)
            ) { start, duration in
                Task {
                    await viewModel.reschedule(booking, to: start, durationMinutes: duration)
                }
            }
        }
        .sheet(item: $reviewTask) { task in
            ReviewComposerSheet(task: task) { responses in
                Task {
                    await viewModel.submitReviews(task: task, responses: responses)
                    await MainActor.run {
                        reviewTask = nil
                    }
                }
            }
        }
        .confirmationDialog(
            "Cancel session?",
            isPresented: $showCancelDialog,
            titleVisibility: .visible,
            presenting: bookingToCancel
        ) { booking in
            Button("Cancel session", role: .destructive) {
                Task {
                    await viewModel.cancel(booking)
                }
                bookingToCancel = nil
            }
            Button("Keep session", role: .cancel) {
                bookingToCancel = nil
            }
        } message: { _ in
            Text("This will notify everyone that the session is cancelled.")
        }
        .sheet(item: $bookingForDetails) { booking in
            BookingDetailSheet(booking: booking)
        }
        .sheet(isPresented: $showHistorySheet) {
            PastSessionsLogView(onSelect: { booking in
                bookingForDetails = booking
            })
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Toggle(isOn: $viewModel.hideCancelled) {
                        Label("Hide cancelled sessions", systemImage: viewModel.hideCancelled ? "eye.slash" : "eye")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .imageScale(.large)
                }
            }
        }
        .onChange(of: appState.targetBookingID) { _, newValue in
            guard let bookingId = newValue else { return }
            Task {
                if let booking = await viewModel.reloadBookingIfNeeded(withId: bookingId) {
                    await MainActor.run {
                        bookingForDetails = booking
                    }
                } else {
                    await MainActor.run {
                        Logger.log("Booking deep link not found: \(bookingId)")
                    }
                }
                await MainActor.run {
                    appState.targetBookingID = nil
                }
            }
        }
    }

    private var historyButton: some View {
        Button {
            showHistorySheet = true
        } label: {
            Label("View session history", systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }
}

private struct PendingReviewsSection: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let tasks: [BookingInboxViewModel.ReviewTask]
    let onSelect: (BookingInboxViewModel.ReviewTask) -> Void
    let onHide: (BookingInboxViewModel.ReviewTask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Awaiting your review", systemImage: "star.bubble")
                .font(.headline)
                .padding(.horizontal)

            LazyVStack(spacing: 12) {
                ForEach(tasks) { task in
                    Button {
                        onSelect(task)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(taskTitle(for: task))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(viewModel.reviewSubtitle(for: task))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(task.targets) { target in
                                Text(viewModel.reviewPrompt(for: target))
                                    .font(.footnote)
                                    .foregroundStyle(.primary)
                            }

                            if task.targets.count > 1 {
                                Text("Rate both the studio and engineer together.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Hide reminder", role: .destructive) {
                                onHide(task)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.borderless)
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 4)
    }

    private func taskTitle(for task: BookingInboxViewModel.ReviewTask) -> String {
        if task.targets.count > 1 {
            return viewModel.studioName(for: task.booking.studioId)
        }
        if let target = task.targets.first {
            return viewModel.revieweeName(for: target)
        }
        return "Review"
    }
}

private struct BookingListView: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let pending: [Booking]
    let scheduled: [Booking]
    let title: String
    let subtitle: String
    let allowPendingActions: Bool
    let onReschedule: (Booking) -> Void
    let onCancel: (Booking) -> Void
    let onSelect: (Booking) -> Void

    private var filteredPending: [Booking] {
        guard viewModel.hideCancelled else { return pending }
        return pending.filter { $0.status != .cancelled }
    }

    private var filteredScheduled: [Booking] {
        guard viewModel.hideCancelled else { return scheduled }
        return scheduled.filter { $0.status != .cancelled }
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if filteredPending.isEmpty == false {
                Section(title) {
                    ForEach(filteredPending) { booking in
                        BookingRow(
                            booking: booking,
                            showActions: allowPendingActions && viewModel.canAct(on: booking),
                            onReschedule: onReschedule,
                            onCancel: onCancel
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(booking) }
                    }
                }
            }

            if filteredScheduled.isEmpty == false {
                Section(subtitle) {
                    ForEach(filteredScheduled) { booking in
                        BookingRow(
                            booking: booking,
                            showActions: false,
                            onReschedule: onReschedule,
                            onCancel: onCancel
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(booking) }
                    }
                }
            }

            if filteredPending.isEmpty && filteredScheduled.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("We’ll let you know when a new booking comes in.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private struct BookingCalendarView: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let allowPendingActions: Bool
    let onReschedule: (Booking) -> Void
    let onCancel: (Booking) -> Void
    let onSelect: (Booking) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if viewModel.calendarDaySummaries.isEmpty {
                    ContentUnavailableView(
                        "No bookings yet",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Once sessions are scheduled, they’ll appear on your calendar.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    dayChips

                    DatePicker(
                        "Session date",
                        selection: $viewModel.selectedCalendarDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(selectedDateLabel)
                            .font(.headline)

                        let bookings = viewModel.bookings(for: viewModel.selectedCalendarDate)
                        if bookings.isEmpty {
                            ContentUnavailableView(
                                "No sessions this day",
                                systemImage: "calendar.badge.clock",
                                description: Text("Pick another date to see scheduled sessions.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(bookings) { booking in
                                    BookingRow(
                                        booking: booking,
                                        showActions: allowPendingActions && viewModel.canAct(on: booking),
                                        onReschedule: onReschedule,
                                        onCancel: onCancel
                                    )
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    )
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(booking) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var dayChips: some View {
        let summaries = viewModel.calendarDaySummaries
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(summaries) { summary in
                    let isSelected = Calendar.current.isDate(summary.date, inSameDayAs: viewModel.selectedCalendarDate)
                    Button {
                        viewModel.selectedCalendarDate = summary.date
                    } label: {
                        VStack(spacing: 4) {
                            Text(summary.weekday)
                                .font(.caption.weight(.semibold))
                            Text(summary.label)
                                .font(.footnote)
                            Text("\(summary.bookings.count)" + (summary.bookings.count == 1 ? " session" : " sessions"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var selectedDateLabel: String {
        BookingCalendarView.fullDateFormatter.string(from: viewModel.selectedCalendarDate)
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct EngineerScheduleView: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                ForEach(viewModel.engineerSchedulesForSelectedDate) { schedule in
                    EngineerScheduleRow(schedule: schedule, labelProvider: viewModel)
                        .padding(.horizontal, 16)
                }

                if viewModel.engineerSchedulesForSelectedDate.isEmpty {
                    ContentUnavailableView(
                        "No engineers",
                        systemImage: "person.crop.rectangle.badge.questionmark",
                        description: Text("Invite engineers to your studio to see their schedules here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engineer schedule")
                .font(.headline)
            Text("Showing sessions for \(formattedDate(viewModel.selectedCalendarDate))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

private struct EngineerOpenTimesView: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel
    @State private var selectedRoomIds: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            dateSelector
            Divider()
                .padding(.horizontal)
                .padding(.top, 8)

            content
        }
        .onAppear(perform: syncSelections)
        .onChange(of: viewModel.openTimesSections) { _ in
            syncSelections()
        }
    }

    private var dateSelector: some View {
        HStack(spacing: 12) {
            DatePicker(
                "Selected date",
                selection: Binding(
                    get: { viewModel.selectedCalendarDate },
                    set: { viewModel.selectedCalendarDate = $0 }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()

            Spacer()

            HStack(spacing: 12) {
                Button {
                    shiftSelectedDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    shiftSelectedDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingOpenTimes {
            ProgressView("Loading open times…")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding()
        } else if let error = viewModel.openTimesError, error.isEmpty == false {
            ContentUnavailableView(
                "Unable to load open times",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
        } else if let message = viewModel.openTimesMessage, message.isEmpty == false {
            ContentUnavailableView(
                "No studios yet",
                systemImage: "music.note.house",
                description: Text(message)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
        } else if viewModel.openTimesSections.isEmpty {
            ContentUnavailableView(
                "No availability",
                systemImage: "calendar.badge.xmark",
                description: Text("Pick a different date to see open rooms.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
        } else {
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.openTimesSections) { section in
                        sectionView(section)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: BookingInboxViewModel.OpenTimesSection) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.studio.name)
                        .font(.headline)
                    Text(formattedDate(for: section))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(timezoneDescription(for: section.timezone))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                roomSelector(for: section)
            }

            if let message = section.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                roomWindows(for: section)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private func roomSelector(for section: BookingInboxViewModel.OpenTimesSection) -> some View {
        if let room = selectedRoom(in: section) {
            if section.rooms.count <= 1 {
                Text(room.room.name)
                    .font(.subheadline.weight(.semibold))
            } else {
                Menu {
                    ForEach(section.rooms) { candidate in
                        Button {
                            selectedRoomIds[section.id] = candidate.id
                        } label: {
                            if candidate.id == room.id {
                                Label(candidate.room.name, systemImage: "checkmark")
                            } else {
                                Text(candidate.room.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(room.room.name)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }
        } else {
            Text("No rooms")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func roomWindows(for section: BookingInboxViewModel.OpenTimesSection) -> some View {
        if let room = selectedRoom(in: section) {
            if room.windows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No open windows")
                        .font(.callout.weight(.semibold))
                    Text("All sessions are booked for this room on the selected date.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(room.windows) { window in
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(window.formattedRange)
                                .font(.body)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                        )
                    }
                }
            }
        } else {
            Text("No rooms available.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func syncSelections() {
        var updated: [String: String] = [:]
        let sections = viewModel.openTimesSections
        let existing = selectedRoomIds

        for section in sections {
            if let current = existing[section.id],
               section.rooms.contains(where: { $0.id == current }) {
                updated[section.id] = current
            } else if let defaultId = section.defaultRoomId {
                updated[section.id] = defaultId
            } else if let firstId = section.rooms.first?.id {
                updated[section.id] = firstId
            }
        }

        if updated != selectedRoomIds {
            selectedRoomIds = updated
        }
    }

    private func selectedRoom(in section: BookingInboxViewModel.OpenTimesSection) -> BookingInboxViewModel.OpenTimesSection.OpenRoom? {
        let preferred = selectedRoomIds[section.id]
        return section.rooms.first { $0.id == preferred } ?? section.rooms.first
    }

    private func formattedDate(for section: BookingInboxViewModel.OpenTimesSection) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.timeZone = section.timezone
        return formatter.string(from: section.dayStart)
    }

    private func timezoneDescription(for timezone: TimeZone) -> String {
        if let localized = timezone.localizedName(for: .shortStandard, locale: .current) {
            return localized
        }
        return timezone.identifier
    }

    private func shiftSelectedDate(by days: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: days, to: viewModel.selectedCalendarDate) {
            viewModel.selectedCalendarDate = newDate
        }
    }
}

private struct EngineerScheduleRow: View {
    let schedule: BookingInboxViewModel.EngineerSchedule
    let labelProvider: BookingInboxViewModel

    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(labelProvider.displayName(forUser: schedule.engineerId))
                        .font(.subheadline.weight(.semibold))
                    if let profile = schedule.profile, profile.profileDetails.fieldOne.isEmpty == false {
                        Text(profile.profileDetails.fieldOne)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if schedule.bookings.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    Text("No sessions today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                }
                .frame(height: 48)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(schedule.bookings) { booking in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(labelProvider.roomName(for: booking.roomId))
                                    .font(.caption.weight(.semibold))
                                Text(rangeLabel(for: booking))
                                    .font(.footnote)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.18))
                            )
                            .foregroundStyle(Color.primary)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = schedule.profile?.profileImageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }

    private func rangeLabel(for booking: Booking) -> String {
        let start = booking.requestedStart
        let end = booking.requestedEnd
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}

private struct BookingDetailSheet: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.di) private var di
    @Environment(\.dismiss) private var dismiss

    @State private var localBooking: Booking
    @State private var isLoadingChat = false
    @State private var isCompleting = false
    @State private var chatThread: ChatThread?
    @State private var errorMessage: String?

    init(booking: Booking) {
        _localBooking = State(initialValue: booking)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sessionCard
                    if showSessionActions {
                        sessionActionsCard
                    }
                    locationCard
                    participantsCard
                    notesCard
                    messageCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .background(Theme.appBackground)
            .navigationTitle("Session details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $chatThread) { thread in
            NavigationStack {
                ChatDetailView(
                    viewModel: ChatDetailViewModel(
                        thread: thread,
                        chatService: di.chatService,
                        storageService: di.storageService,
                        appState: appState
                    )
                )
            }
        }
        .alert(errorMessage ?? "", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        }
    }

    private var showSessionActions: Bool {
        viewModel.canComplete(localBooking)
    }

    private var sessionCard: some View {
        detailCard(title: "Session") {
            VStack(alignment: .leading, spacing: 8) {
                Label(dateRangeText, systemImage: "calendar")
                Label(durationText, systemImage: "clock")

                HStack(spacing: 8) {
                    Image(systemName: statusDescriptor.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusDescriptor.color)
                    Text(statusDescriptor.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusDescriptor.color)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(statusDescriptor.color.opacity(0.16), in: Capsule())

                if let pricingText {
                    Label(pricingText, systemImage: "creditcard")
                }

                if localBooking.instantBook {
                    Label("Instantly confirmed", systemImage: "bolt.fill")
                        .foregroundStyle(Color.green)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var sessionActionsCard: some View {
        detailCard(title: "Session actions") {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.canComplete(localBooking) {
                    Button {
                        Task { await markSessionCompleted() }
                    } label: {
                        if isCompleting {
                            HStack {
                                ProgressView()
                                Text("Completing…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Mark as completed", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isCompleting)
                    Text("Move this session to your history and unlock post-session tasks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var locationCard: some View {
        detailCard(title: "Location") {
            if let studio = viewModel.studio(for: localBooking.studioId) {
                Label(studio.name, systemImage: "building.2")
                    .font(.subheadline.weight(.semibold))
                if let addressLine = addressLine(for: studio), addressLine.isEmpty == false {
                    Label(addressLine, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(viewModel.studioName(for: localBooking.studioId), systemImage: "building.2")
                    .font(.subheadline.weight(.semibold))
                Text("Studio details unavailable")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var participantsCard: some View {
        detailCard(title: "Participants") {
            VStack(alignment: .leading, spacing: 14) {
                participantEntry(
                    icon: "person",
                    role: "Artist",
                    userId: localBooking.artistId,
                    profileType: .artist,
                    contact: viewModel.userProfile(for: localBooking.artistId)?.contact
                )

                participantEntry(
                    icon: "person.crop.rectangle",
                    role: "Engineer",
                    userId: localBooking.engineerId,
                    profileType: .engineer,
                    contact: viewModel.userProfile(for: localBooking.engineerId)?.contact
                )

                if let studio = viewModel.studio(for: localBooking.studioId) {
                    let ownerName = viewModel.displayName(forUser: studio.ownerId)
                    participantRow(
                        icon: "building",
                        role: "Studio",
                        name: studio.name,
                        subtitle: ownerName == studio.name ? nil : "Owner: \(ownerName)",
                        contact: viewModel.userProfile(for: studio.ownerId)?.contact
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var notesCard: some View {
        if localBooking.notes.isEmpty == false {
            detailCard(title: "Notes") {
                Text(localBooking.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var messageCard: some View {
        detailCard(title: "Coordinate") {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    Task { await openChat() }
                } label: {
                    if isLoadingChat {
                        HStack {
                            ProgressView()
                            Text("Opening chat…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Message studio & engineer", systemImage: "message")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingChat)

                Text("Start a conversation to finalize logistics with everyone involved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let conversationId = localBooking.conversationId {
                    Label {
                        Text("Linked chat ID: \(conversationId)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "link")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func detailCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }

    private enum ParticipantProfileType {
        case artist
        case engineer
    }

    @ViewBuilder
    private func participantEntry(
        icon: String,
        role: String,
        userId: String,
        profileType: ParticipantProfileType? = nil,
        subtitle: String? = nil,
        contact: UserContactInfo? = nil
    ) -> some View {
        let name = viewModel.displayName(forUser: userId)
        if let profile = viewModel.userProfile(for: userId) {
            if profile.accountType.isEngineer || profileType == .engineer {
                NavigationLink {
                    EngineerDetailView(engineerId: profile.id, profile: profile)
                } label: {
                    participantRow(
                        icon: icon,
                        role: role,
                        name: name,
                        subtitle: subtitle,
                        contact: contact
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if profile.accountType.isArtistFamily || profileType == .artist {
                NavigationLink {
                    ArtistDetailView(artistId: profile.id, profile: profile)
                } label: {
                    participantRow(
                        icon: icon,
                        role: role,
                        name: name,
                        subtitle: subtitle,
                        contact: contact
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                participantRow(
                    icon: icon,
                    role: role,
                    name: name,
                    subtitle: subtitle,
                    contact: contact
                )
            }
        } else if let profileType {
            switch profileType {
            case .engineer:
                NavigationLink {
                    EngineerDetailView(engineerId: userId)
                } label: {
                    participantRow(
                        icon: icon,
                        role: role,
                        name: name,
                        subtitle: subtitle,
                        contact: contact
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            case .artist:
                NavigationLink {
                    ArtistDetailView(artistId: userId)
                } label: {
                    participantRow(
                        icon: icon,
                        role: role,
                        name: name,
                        subtitle: subtitle,
                        contact: contact
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } else {
            participantRow(
                icon: icon,
                role: role,
                name: name,
                subtitle: subtitle,
                contact: contact
            )
        }
    }

    private func participantRow(
        icon: String,
        role: String,
        name: String,
        subtitle: String? = nil,
        contact: UserContactInfo? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
            }

            if let contact {
                if contact.email.isEmpty == false {
                    Label(contact.email, systemImage: "envelope")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
                if contact.phoneNumber.isEmpty == false {
                    Label(contact.phoneNumber, systemImage: "phone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 26)
                }
            }
        }
    }

    @MainActor
    private func openChat() async {
        guard isLoadingChat == false else { return }
        guard let currentUser = appState.currentUser else {
            errorMessage = "Sign in to message participants."
            return
        }

        isLoadingChat = true
        defer { isLoadingChat = false }

        do {
            let thread: ChatThread
            if let existingId = localBooking.conversationId {
                thread = try await di.chatService.thread(withId: existingId)
            } else {
                let participants = try buildChatParticipants(excluding: currentUser.id)
                guard participants.isEmpty == false else {
                    throw BookingDetailError.missingParticipants
                }

                let creator = ChatParticipant(user: currentUser)
                let kind: ChatThread.Kind = participants.count > 1 ? .group : .direct
                let settings = kind == .group
                    ? ChatThread.GroupSettings(
                        name: "\(viewModel.studioName(for: localBooking.studioId)) Session",
                        photo: nil,
                        allowsParticipantEditing: true
                    )
                    : nil

                thread = try await di.chatService.createThread(
                    creator: creator,
                    participants: participants,
                    kind: kind,
                    groupSettings: settings,
                    project: nil
                )

                localBooking.conversationId = thread.id
                let bookingSnapshot = localBooking
                Task {
                    await viewModel.attachConversation(thread.id, to: bookingSnapshot)
                }
            }

            chatThread = thread
        } catch {
            if let bookingError = error as? BookingDetailError {
                self.errorMessage = bookingError.errorDescription ?? "Unable to start the chat."
            } else {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func markSessionCompleted() async {
        guard isCompleting == false else { return }
        isCompleting = true
        await viewModel.complete(localBooking)
        await MainActor.run {
            localBooking.status = .completed
            isCompleting = false
        }
    }

    private func buildChatParticipants(excluding currentUserId: String) throws -> [ChatParticipant] {
        guard let studio = viewModel.studio(for: localBooking.studioId) else {
            throw BookingDetailError.missingStudio
        }

        var participants: [ChatParticipant] = [ChatParticipant(studio: studio)]

        if localBooking.engineerId != currentUserId {
            guard let engineer = viewModel.userProfile(for: localBooking.engineerId) else {
                throw BookingDetailError.missingEngineer
            }
            participants.append(ChatParticipant(user: engineer))
        }

        if localBooking.artistId != currentUserId {
            guard let artist = viewModel.userProfile(for: localBooking.artistId) else {
                throw BookingDetailError.missingArtist
            }
            participants.append(ChatParticipant(user: artist))
        }

        var unique: [String: ChatParticipant] = [:]
        for participant in participants where participant.id != currentUserId {
            unique[participant.id] = participant
        }
        return Array(unique.values)
    }

    private func addressLine(for studio: Studio) -> String? {
        switch (studio.address.isEmpty, studio.city.isEmpty) {
        case (true, true):
            return nil
        case (false, true):
            return studio.address
        case (true, false):
            return studio.city
        case (false, false):
            return "\(studio.address), \(studio.city)"
        }
    }

    private var dateRangeText: String {
        Self.dateIntervalFormatter.string(from: localBooking.requestedStart, to: localBooking.requestedEnd)
    }

    private var durationText: String {
        if let formatted = Self.durationFormatter.string(from: TimeInterval(localBooking.durationMinutes * 60)) {
            return formatted
        }
        return "\(localBooking.durationMinutes) minutes"
    }

    private var pricingText: String? {
        guard let pricing = localBooking.pricing else { return nil }
        if let formatted = Self.currencyFormatter(currencyCode: pricing.currency).string(from: NSNumber(value: pricing.total)) {
            return "Total: \(formatted)"
        }
        return "Total: \(pricing.currency) \(pricing.total)"
    }

    private var statusDescriptor: (title: String, color: Color, icon: String) {
        if localBooking.status == .pending {
            switch (localBooking.approval.requiresStudioApproval, localBooking.approval.requiresEngineerApproval) {
            case (true, true):
                return ("Pending approval", .orange, "hourglass")
            case (true, false):
                return ("Awaiting studio", .orange, "building.2")
            case (false, true):
                return ("Awaiting engineer", .orange, "person.crop.rectangle")
            case (false, false):
                return ("Pending", .orange, "hourglass")
            }
        }

        switch localBooking.status {
        case .confirmed:
            return ("Confirmed", .green, "checkmark")
        case .completed:
            return ("Completed", .blue, "checkmark.seal")
        case .cancelled:
            return ("Cancelled", .red, "xmark")
        case .rescheduled:
            return ("Rescheduled", .purple, "arrow.uturn.right")
        case .pending:
            return ("Pending", .orange, "hourglass")
        }
    }

    private static let dateIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = [.dropLeading]
        return formatter
    }()

    private static func currencyFormatter(currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter
    }
}

private struct PastSessionsLogView: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel
    @Environment(\.dismiss) private var dismiss

    let onSelect: (Booking) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if groupedHistory.isEmpty {
                    ContentUnavailableView(
                        "No past sessions",
                        systemImage: "clock.badge.questionmark",
                        description: Text("Completed and cancelled sessions will show up here for reference.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.appBackground)
                } else {
                    List {
                        ForEach(groupedHistory) { section in
                            Section(section.title) {
                                ForEach(section.bookings) { booking in
                                    PastSessionRow(booking: booking) { selected in
                                        onSelect(selected)
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Theme.appBackground)
                }
            }
            .navigationTitle("Session history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var groupedHistory: [HistorySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: viewModel.pastBookings) { booking -> Date in
            let components = calendar.dateComponents([.year, .month], from: booking.requestedStart)
            return calendar.date(from: components) ?? booking.requestedStart
        }
        return grouped
            .map { entry in
                HistorySection(date: entry.key, bookings: entry.value.sorted { $0.requestedStart > $1.requestedStart })
            }
            .sorted { $0.date > $1.date }
    }

    private struct HistorySection: Identifiable {
        let date: Date
        let bookings: [Booking]

        var id: Date { date }

        var title: String {
            Self.titleFormatter.string(from: date)
        }

        private static let titleFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "LLLL yyyy"
            return formatter
        }()
    }
}

private struct PastSessionRow: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let booking: Booking
    let onSelect: (Booking) -> Void

    @State private var isCompleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(dateRangeText)
                    .font(.headline)
                Spacer()
                statusLabel
            }

            Label("Studio: \(viewModel.studioName(for: booking.studioId))", systemImage: "building.2")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label("Artist: \(viewModel.displayName(forUser: booking.artistId))", systemImage: "person")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Label("Engineer: \(viewModel.displayName(forUser: booking.engineerId))", systemImage: "person.crop.rectangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if booking.notes.isEmpty == false {
                Text(booking.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    onSelect(booking)
                } label: {
                    Label("View details", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)

                if viewModel.canComplete(booking) {
                    Button {
                        Task { await markCompleted() }
                    } label: {
                        if isCompleting {
                            ProgressView()
                        } else {
                            Label("Mark completed", systemImage: "checkmark.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isCompleting)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(booking)
        }
    }

    private var statusLabel: some View {
        let descriptor = statusDescriptor
        return Label(descriptor.text, systemImage: descriptor.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(descriptor.color)
            .background(descriptor.color.opacity(0.14), in: Capsule())
    }

    private var statusDescriptor: (text: String, icon: String, color: Color) {
        if booking.status == .pending {
            if booking.approval.requiresEngineerApproval && booking.approval.requiresStudioApproval {
                return ("Pending", "hourglass", .orange)
            }
            if booking.approval.requiresStudioApproval {
                return ("Awaiting studio", "building.2", .orange)
            }
            if booking.approval.requiresEngineerApproval {
                return ("Awaiting engineer", "person.crop.rectangle", .orange)
            }
            return ("Pending", "hourglass", .orange)
        }

        switch booking.status {
        case .confirmed:
            return ("Confirmed", "checkmark.circle", .green)
        case .completed:
            return ("Completed", "checkmark.seal", .blue)
        case .cancelled:
            return ("Cancelled", "xmark", .red)
        case .rescheduled:
            return ("Rescheduled", "arrow.uturn.right", .purple)
        case .pending:
            return ("Pending", "hourglass", .orange)
        }
    }

    private var dateRangeText: String {
        Self.dateIntervalFormatter.string(from: booking.requestedStart, to: booking.requestedEnd)
    }

    private static let dateIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private func markCompleted() async {
        guard isCompleting == false else { return }
        isCompleting = true
        await viewModel.complete(booking)
        await MainActor.run { isCompleting = false }
    }
}

private enum BookingDetailError: LocalizedError {
    case missingStudio
    case missingEngineer
    case missingArtist
    case missingParticipants

    var errorDescription: String? {
        switch self {
        case .missingStudio:
            return "Studio details are missing. Try refreshing your bookings."
        case .missingEngineer:
            return "We couldn't load the engineer's profile. Refresh and try again."
        case .missingArtist:
            return "We couldn't load the artist profile for this session. Refresh and try again."
        case .missingParticipants:
            return "We need at least one other participant to start a chat."
        }
    }
}

private struct BookingRow: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let booking: Booking
    let showActions: Bool
    let onReschedule: (Booking) -> Void
    let onCancel: (Booking) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            details
            if showActions {
                actions
            }
        }
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(dateRange)
                .font(.headline)
            Spacer()
            let badge = statusBadge
            Text(badge.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badge.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(badge.color.opacity(0.14), in: Capsule())

            let canCancel = viewModel.canCancel(booking)
            let canReschedule = viewModel.canReschedule(booking)
            let canComplete = viewModel.canComplete(booking)
            if canCancel || canReschedule || canComplete {
                Menu {
                    if canComplete {
                        Button("Mark completed") {
                            Task { await viewModel.complete(booking) }
                        }
                    }
                    if canReschedule {
                        Button("Reschedule") {
                            onReschedule(booking)
                        }
                    }
                    if canCancel {
                        Button("Cancel session", role: .destructive) {
                            onCancel(booking)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Artist: \(viewModel.displayName(forUser: booking.artistId))", systemImage: "person")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if viewModel.viewerRole == .studioOwner {
                Label("Engineer: \(viewModel.displayName(forUser: booking.engineerId))", systemImage: "person.crop.rectangle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Label("Studio: \(viewModel.studioName(for: booking.studioId))", systemImage: "building.2")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Room: \(viewModel.roomName(for: booking.roomId))", systemImage: "music.mic")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if booking.notes.isEmpty == false {
                Text(booking.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button(role: .destructive) {
                Task { await viewModel.decline(booking) }
            } label: {
                if viewModel.isPerformingAction(for: booking) {
                    ProgressView()
                } else {
                    Text("Decline")
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isPerformingAction(for: booking))

            Button {
                Task { await viewModel.approve(booking) }
            } label: {
                if viewModel.isPerformingAction(for: booking) {
                    ProgressView()
                } else {
                    Text("Approve")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(viewModel.isPerformingAction(for: booking))
        }
    }

    private var dateRange: String {
        let start = booking.requestedStart
        let end = booking.requestedEnd
        return Self.dateFormatter.string(from: start) + " – " + Self.timeFormatter.string(from: end)
    }

    private var statusBadge: (text: String, color: Color) {
        if booking.status == .pending {
            let needsStudio = booking.approval.requiresStudioApproval
            let needsEngineer = booking.approval.requiresEngineerApproval
            switch (needsStudio, needsEngineer) {
            case (true, true):
                return ("Pending", .orange)
            case (true, false):
                return ("Awaiting studio", .orange)
            case (false, true):
                return ("Awaiting engineer", .orange)
            case (false, false):
                return ("Pending", .orange)
            }
        }
        switch booking.status {
        case .confirmed:
            return ("Confirmed", .green)
        case .completed:
            return ("Completed", .blue)
        case .cancelled:
            return ("Cancelled", .red)
        case .rescheduled:
            return ("Rescheduled", .purple)
        case .pending:
            return ("Pending", .orange)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct RescheduleBookingSheet: View {
    @Environment(\.dismiss) private var dismiss

    let booking: Booking
    let durationOptions: [Int]
    let onSubmit: (Date, Int) -> Void

    @State private var startDate: Date
    @State private var durationMinutes: Int

    init(booking: Booking, durationOptions: [Int], onSubmit: @escaping (Date, Int) -> Void) {
        self.booking = booking
        self.durationOptions = durationOptions.sorted()
        self.onSubmit = onSubmit
        _startDate = State(initialValue: booking.requestedStart)
        _durationMinutes = State(initialValue: booking.durationMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start time") {
                    DatePicker(
                        "Date",
                        selection: $startDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                }

                Section("Duration") {
                    Picker("Duration", selection: $durationMinutes) {
                        ForEach(durationOptions, id: \.self) { minutes in
                            Text(label(for: minutes)).tag(minutes)
                        }
                    }
                }

                Section("Summary") {
                    Text(summaryLabel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSubmit(startDate, durationMinutes)
                        dismiss()
                    }
                }
            }
        }
    }

    private func label(for minutes: Int) -> String {
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }
        return "\(minutes) min"
    }

    private var summaryLabel: String {
        let endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let startString = formatter.string(from: startDate)
        let endString = formatter.string(from: endDate)
        return "Session will run from \(startString) to \(endString)."
    }
}

private struct ReviewComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let task: BookingInboxViewModel.ReviewTask
    let onSubmit: ([BookingInboxViewModel.ReviewTarget: BookingInboxViewModel.ReviewResponse]) -> Void

    @State private var ratings: [String: Int]
    @State private var comments: [String: String]

    init(task: BookingInboxViewModel.ReviewTask, onSubmit: @escaping ([BookingInboxViewModel.ReviewTarget: BookingInboxViewModel.ReviewResponse]) -> Void) {
        self.task = task
        self.onSubmit = onSubmit
        var initialRatings: [String: Int] = [:]
        for target in task.targets {
            initialRatings[target.id] = 5
        }
        _ratings = State(initialValue: initialRatings)
        _comments = State(initialValue: [:])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(viewModel.reviewTitle(for: task)) {
                    Text(viewModel.reviewSubtitle(for: task))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if task.targets.count > 1 {
                        Text("Rate the studio and engineer from this session.")
                            .font(.footnote)
                    }
                }

                ForEach(task.targets) { target in
                    Section(header: Text(viewModel.revieweeName(for: target))) {
                        Text(viewModel.reviewPrompt(for: target))
                            .font(.footnote)

                        ratingRow(for: target)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Comments (optional)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: Binding(
                                get: { comments[target.id] ?? "" },
                                set: { comments[target.id] = $0 }
                            ))
                            .frame(minHeight: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(uiColor: .separator), lineWidth: 1 / UIScreen.main.scale)
                            )
                        }
                        .padding(.top, 6)
                    }
                }

                if viewModel.isSubmittingReview(for: task) {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Submitting…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Leave a review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        onSubmit(buildResponses())
                        dismiss()
                    }
                    .disabled(viewModel.isSubmittingReview(for: task))
                }
            }
        }
    }

    private func ratingRow(for target: BookingInboxViewModel.ReviewTarget) -> some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= (ratings[target.id] ?? 5) ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(value <= (ratings[target.id] ?? 5) ? Color.yellow : Color.secondary)
                    .onTapGesture {
                        ratings[target.id] = value
                    }
            }
            Spacer()
            Text("\(ratings[target.id] ?? 5)/5")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func buildResponses() -> [BookingInboxViewModel.ReviewTarget: BookingInboxViewModel.ReviewResponse] {
        var responses: [BookingInboxViewModel.ReviewTarget: BookingInboxViewModel.ReviewResponse] = [:]
        for target in task.targets {
            let rating = ratings[target.id] ?? 5
            let comment = comments[target.id] ?? ""
            responses[target] = BookingInboxViewModel.ReviewResponse(rating: rating, comment: comment)
        }
        return responses
    }
}

// Preview intentionally omitted – relies on Firestore data.
