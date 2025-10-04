import SwiftUI

struct BookingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BookingFlowViewModel
    @FocusState private var isNotesFocused: Bool

    init(
        studio: Studio,
        preferredEngineerId: String? = nil,
        bookingService: any BookingService,
        firestoreService: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        _viewModel = StateObject(
            wrappedValue: BookingFlowViewModel(
                studio: studio,
                preferredEngineerId: preferredEngineerId,
                bookingService: bookingService,
                firestoreService: firestoreService,
                currentUserProvider: currentUserProvider
            )
        )
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Book Session")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { isNotesFocused = false }
                    }
                }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.startDate) { _ in
            Task {
                await viewModel.refreshQuote()
                await viewModel.refreshEngineerAvailability()
            }
        }
        .onChange(of: viewModel.durationMinutes) { _ in
            Task { await viewModel.refreshQuote() }
        }
        .onChange(of: viewModel.selectedRoom?.id) { _ in
            Task {
                await viewModel.refreshQuote()
                await viewModel.refreshEngineerAvailability()
            }
        }
        .onChange(of: viewModel.selectedEngineer?.id) { _ in
            Task {
                await viewModel.refreshQuote()
                await viewModel.refreshEngineerAvailability()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemGroupedBackground))
        } else if let error = viewModel.loadErrorMessage {
            ContentUnavailableView(
                "We couldn't load booking data",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else {
            bookingForm
        }
    }

    private var bookingForm: some View {
        Form {
            Section("Schedule") {
                DatePicker("Start", selection: $viewModel.startDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)

                Picker("Duration", selection: $viewModel.durationMinutes) {
                    ForEach(viewModel.durationOptions(), id: \.self) { minutes in
                        Text(durationLabel(for: minutes)).tag(minutes)
                    }
                }
            }

            Section("Engineer Availability") {
                if viewModel.isLoadingEngineerAvailability {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if let message = viewModel.engineerAvailabilityMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if viewModel.engineerAvailabilityLines.isEmpty {
                    Text("Select a different day to view open times.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.engineerAvailabilityLines) { line in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "clock")
                                    .foregroundStyle(.primary)
                                    .font(.footnote)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(line.subtitle)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let rooms = viewModel.context?.rooms, rooms.isEmpty == false {
                Section("Room") {
                    Picker("Room", selection: Binding(
                        get: { viewModel.selectedRoom?.id ?? "" },
                        set: { newValue in
                            viewModel.selectedRoom = rooms.first { $0.id == newValue }
                        }
                    )) {
                        ForEach(rooms) { room in
                            roomPickerRow(for: room)
                        }
                    }
                }
            }

            if let engineers = viewModel.context?.engineers, engineers.isEmpty == false {
                Section("Engineer") {
                    Picker("Engineer", selection: Binding(
                        get: { viewModel.selectedEngineer?.id ?? "" },
                        set: { newValue in
                            viewModel.selectedEngineer = engineers.first { $0.id == newValue }
                        }
                    )) {
                        ForEach(engineers) { engineer in
                            Text(engineer.displayName.isEmpty ? engineer.username : engineer.displayName)
                                .tag(engineer.id)
                                .font(.body)
                        }
                    }
                }
            }

            Section("Project Notes") {
                TextEditor(text: $viewModel.notes)
                    .frame(minHeight: 120)
                    .focused($isNotesFocused)
            }

            Section("Summary") {
                if let quote = viewModel.quote {
                    if let room = viewModel.selectedRoom {
                        summaryRow(title: "Room", value: roomSummary(room))
                    }
                    summaryRow(title: "Session", value: formatted(date: quote.startDate))
                    summaryRow(title: "Ends", value: formatted(date: quote.endDate))
                    if let pricing = quote.pricing {
                        let total = NumberFormatter.currency.string(from: NSNumber(value: pricing.total)) ?? "—"
                        summaryRow(title: "Estimate", value: total)
                    }
                    if quote.isInstant {
                        Label("Instantly confirmed", systemImage: "bolt.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Label("Pending approval", systemImage: "hourglass")
                            .foregroundStyle(.orange)
                            .font(.subheadline.weight(.semibold))
                    }
                } else if let error = viewModel.quoteErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else {
                    Text("Select details to see availability")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                PrimaryButton(title: viewModel.isSubmitting ? "Submitting…" : "Submit") {
                    Task { await viewModel.submit() }
                }
                .disabled(viewModel.isSubmitting || viewModel.quote == nil)

                if let submissionError = viewModel.submissionErrorMessage {
                    Text(submissionError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }

                if viewModel.submittedBooking != nil {
                    Text("Request sent! Check your inbox for updates.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                        .task {
                            guard let booking = viewModel.submittedBooking else { return }
                            // For instantly confirmed bookings, close right away.
                            if booking.status == .confirmed {
                                dismiss()
                                return
                            }

                            // For pending requests, give users a brief acknowledgement before closing.
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            dismiss()
                        }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func roomPickerRow(for room: Room) -> some View {
        HStack {
            Text(room.name)
            Spacer()
            if let rate = room.hourlyRate,
               let rateText = NumberFormatter.currency.string(from: NSNumber(value: rate)) {
                Text(rateText)
                    .foregroundStyle(.secondary)
            }
        }
        .tag(room.id)
    }

    private func roomSummary(_ room: Room) -> String {
        if let rate = room.hourlyRate,
           let rateText = NumberFormatter.currency.string(from: NSNumber(value: rate)) {
            return "\(room.name) • \(rateText)/hr"
        }
        return room.name
    }

    private func formatted(date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func durationLabel(for minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        if remainder == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainder)m"
    }
}

private extension NumberFormatter {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}
