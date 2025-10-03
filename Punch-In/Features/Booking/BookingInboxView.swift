import SwiftUI

struct BookingInboxView: View {
    @StateObject private var viewModel: BookingInboxViewModel

    init(
        bookingService: any BookingService,
        firestoreService: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        _viewModel = StateObject(
            wrappedValue: BookingInboxViewModel(
                bookingService: bookingService,
                firestoreService: firestoreService,
                currentUserProvider: currentUserProvider
            )
        )
    }

    var body: some View {
        content
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.viewerRole {
        case .unknown:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
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

    let pending: [Booking]
    let scheduled: [Booking]
    let title: String
    let subtitle: String
    let allowPendingActions: Bool

    @State private var bookingToReschedule: Booking?
    @State private var bookingToCancel: Booking?
    @State private var showCancelDialog = false

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

            if viewModel.displayMode == .list {
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
                    }
                )
            } else if viewModel.displayMode == .schedule {
                EngineerScheduleView()
            } else {
                BookingCalendarView(
                    allowPendingActions: allowPendingActions,
                    onReschedule: { bookingToReschedule = $0 },
                    onCancel: { booking in
                        bookingToCancel = booking
                        showCancelDialog = true
                    }
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

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if !pending.isEmpty {
                Section(title) {
                    ForEach(pending) { booking in
                        BookingRow(
                            booking: booking,
                            showActions: allowPendingActions && viewModel.canAct(on: booking),
                            onReschedule: onReschedule,
                            onCancel: onCancel
                        )
                    }
                }
            }

            if !scheduled.isEmpty {
                Section(subtitle) {
                    ForEach(scheduled) { booking in
                        BookingRow(
                            booking: booking,
                            showActions: false,
                            onReschedule: onReschedule,
                            onCancel: onCancel
                        )
                    }
                }
            }

            if pending.isEmpty && scheduled.isEmpty {
                ContentUnavailableView(
                    "Nothing to review",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("We’ll let you know when a new booking comes in.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .listStyle(.insetGrouped)
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

            if viewModel.canCancel(booking) || viewModel.canReschedule(booking) {
                Menu {
                    if viewModel.canReschedule(booking) {
                        Button("Reschedule") {
                            onReschedule(booking)
                        }
                    }
                    if viewModel.canCancel(booking) {
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

// Preview intentionally omitted – relies on Firestore data.
