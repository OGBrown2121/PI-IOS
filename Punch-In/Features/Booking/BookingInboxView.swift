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

    var body: some View {
        VStack(spacing: 12) {
            Picker("Display Mode", selection: $viewModel.displayMode) {
                ForEach(BookingInboxViewModel.DisplayMode.allCases) { mode in
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
                    allowPendingActions: allowPendingActions
                )
            } else {
                BookingCalendarView(allowPendingActions: allowPendingActions)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct BookingListView: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let pending: [Booking]
    let scheduled: [Booking]
    let title: String
    let subtitle: String
    let allowPendingActions: Bool

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
                            showActions: allowPendingActions && viewModel.canAct(on: booking)
                        )
                    }
                }
            }

            if !scheduled.isEmpty {
                Section(subtitle) {
                    ForEach(scheduled) { booking in
                        BookingRow(booking: booking, showActions: false)
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
                                        showActions: allowPendingActions && viewModel.canAct(on: booking)
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

private struct BookingRow: View {
    @EnvironmentObject private var viewModel: BookingInboxViewModel

    let booking: Booking
    let showActions: Bool

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
        HStack {
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

// Preview intentionally omitted – relies on Firestore data.
