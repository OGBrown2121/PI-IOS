import SwiftUI

private struct RoomFormData {
    var id: String?
    var name: String = ""
    var description: String = ""
    var hourlyRate: String = ""
    var capacity: String = ""
    var amenities: String = ""

    init() {}

    init(room: Room) {
        id = room.id
        name = room.name
        description = room.description
        if let rate = room.hourlyRate {
            hourlyRate = NumberFormatter.decimal.string(from: NSNumber(value: rate)) ?? ""
        }
        if let capacityValue = room.capacity {
            capacity = String(capacityValue)
        }
        if room.amenities.isEmpty == false {
            amenities = room.amenities.joined(separator: ", ")
        }
    }

    var parsedHourlyRate: Double? {
        let normalized = hourlyRate.replacingOccurrences(of: ",", with: ".")
        return Double(normalized.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var parsedCapacity: Int? {
        Int(capacity.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var parsedAmenities: [String] {
        amenities
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }
}

private enum RoomField: Hashable {
    case name
    case rate
    case capacity
    case amenities
}

private extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let currencyShort: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter
    }()
}

struct StudioAvailabilityManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: StudioAvailabilityManagementViewModel

    @State private var newBlockStart = Date()
    @State private var newBlockEnd = Date().addingTimeInterval(3600)
    @State private var newBlockRoomId: String?
    @State private var newBlockNote: String = ""

    @State private var recurringWeekday = 1
    @State private var recurringStartTime = Calendar.current.startOfDay(for: Date()).addingTimeInterval(10 * 3600)
    @State private var recurringDurationMinutes = 8 * 60

    @State private var isPresentingRoomEditor = false
    @State private var roomForm = RoomFormData()
    @State private var roomFormError: String?
    @FocusState private var focusedRoomField: RoomField?

    init(
        studio: Studio,
        firestore: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        _viewModel = StateObject(
            wrappedValue: StudioAvailabilityManagementViewModel(
                studio: studio,
                firestore: firestore,
                currentUserProvider: currentUserProvider
            )
        )
    }

    var body: some View {
        List {
            studioHeaderSection
            roomsSection
            recurringHoursSection
            addRecurringSection
            availabilitySection
            addBlockSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Studio Availability")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .task { await viewModel.load() }
        .onAppear {
            if newBlockRoomId == nil {
                newBlockRoomId = viewModel.rooms.first?.id
            }
        }
        .onChange(of: viewModel.rooms) { rooms in
            if newBlockRoomId == nil {
                newBlockRoomId = rooms.first?.id
            }
        }
        .alert("Update", isPresented: Binding(
            get: { viewModel.persistMessage != nil && viewModel.persistMessage != "" },
            set: { value in
                if value == false { viewModel.persistMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) { viewModel.persistMessage = nil }
        } message: {
            Text(viewModel.persistMessage ?? "")
        }
        .sheet(isPresented: $isPresentingRoomEditor) {
            NavigationStack {
                Form {
                    Section("Room Details") {
                        TextField("Name", text: $roomForm.name)
                            .focused($focusedRoomField, equals: .name)

                        TextField("Description", text: $roomForm.description, axis: .vertical)
                            .lineLimit(1...3)

                        TextField("Hourly rate", text: $roomForm.hourlyRate)
                            .keyboardType(.decimalPad)
                            .focused($focusedRoomField, equals: .rate)

                        TextField("Capacity", text: $roomForm.capacity)
                            .keyboardType(.numberPad)
                            .focused($focusedRoomField, equals: .capacity)

                        TextField("Amenities (comma separated)", text: $roomForm.amenities)
                            .focused($focusedRoomField, equals: .amenities)
                    }

                    if let error = roomFormError {
                        Section {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .navigationTitle(roomForm.id == nil ? "Add Room" : "Edit Room")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isPresentingRoomEditor = false
                            roomFormError = nil
                            focusedRoomField = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                let error = await viewModel.saveRoom(
                                    id: roomForm.id,
                                    name: roomForm.name,
                                    description: roomForm.description,
                                    hourlyRate: roomForm.parsedHourlyRate,
                                    capacity: roomForm.parsedCapacity,
                                    amenities: roomForm.parsedAmenities
                                )
                                if let error {
                                    roomFormError = error
                                } else {
                                    roomFormError = nil
                                    isPresentingRoomEditor = false
                                    focusedRoomField = nil
                                }
                            }
                        }
                        .disabled(roomForm.name.trimmed.isEmpty)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focusedRoomField = nil }
                    }
                }
            }
        }
    }

    private var studioHeaderSection: some View {
        Section("Session Approvals") {
            Toggle("Studio must approve sessions", isOn: Binding(
                get: { !viewModel.studio.autoApproveRequests },
                set: { newValue in Task { await viewModel.setStudioRequiresApproval(newValue) } }
            ))
            .toggleStyle(.switch)

            Text("When off, new bookings from approved artists are auto-confirmed unless the engineer still needs to approve.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if viewModel.isPersisting {
                ProgressView()
            }

            if let message = viewModel.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var roomsSection: some View {
        Section("Rooms") {
            if viewModel.rooms.isEmpty {
                Text("Add rooms to set custom pricing and availability.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.rooms) { room in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(room.name)
                                .font(.subheadline.weight(.semibold))
                            if room.isDefault {
                                Label("Default", systemImage: "star.fill")
                                    .labelStyle(.titleOnly)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(.yellow.opacity(0.2))
                                    .cornerRadius(8)
                            }
                            Spacer()
                            if let rate = room.hourlyRate,
                               let rateText = NumberFormatter.currencyShort.string(from: NSNumber(value: rate)) {
                                Text(rateText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if room.description.isEmpty == false {
                            Text(room.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if room.amenities.isEmpty == false {
                            Text(room.amenities.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        roomForm = RoomFormData(room: room)
                        roomFormError = nil
                        isPresentingRoomEditor = true
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task {
                                let error = await viewModel.deleteRoom(room)
                                if let error {
                                    roomFormError = error
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                roomForm = RoomFormData()
                roomFormError = nil
                focusedRoomField = .name
                isPresentingRoomEditor = true
            } label: {
                Label("Add Room", systemImage: "plus")
            }
        }
    }

    private var recurringHoursSection: some View {
        Section("Operating Hours") {
            if viewModel.studio.operatingSchedule.recurringHours.isEmpty {
                Text("No recurring hours set")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.studio.operatingSchedule.recurringHours) { range in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(weekdayName(for: range.weekday))
                                .font(.subheadline.weight(.semibold))
                            Text(hourLabel(for: range))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await viewModel.removeRecurringHour(rangeId: range.id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addRecurringSection: some View {
        Section("Add Recurring Hours") {
            Picker("Day", selection: $recurringWeekday) {
                ForEach(0..<7) { index in
                    Text(weekdayName(for: index)).tag(index)
                }
            }
            DatePicker("Start", selection: $recurringStartTime, displayedComponents: .hourAndMinute)
            Picker("Duration", selection: $recurringDurationMinutes) {
                ForEach([4, 6, 8, 10, 12].map { $0 * 60 }, id: \.self) { minutes in
                    Text(durationLabel(for: minutes)).tag(minutes)
                }
            }
            Button {
                let components = Calendar.current.dateComponents([.hour, .minute], from: recurringStartTime)
                let startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                Task { await viewModel.addRecurringHour(weekday: recurringWeekday, startMinutes: startMinutes, durationMinutes: recurringDurationMinutes) }
            } label: {
                Text("Save Hours")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var availabilitySection: some View {
        Section("Blocks & Holds") {
            if viewModel.availabilityEntries.isEmpty {
                Text("No blocks yet")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.availabilityEntries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entryTitle(entry))
                            .font(.subheadline.weight(.semibold))
                        if let start = entry.startDate, let end = entry.endDate {
                            Text("\(formatted(date: start)) – \(formatted(date: end))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let notes = entry.notes, notes.isEmpty == false {
                            Text(notes)
                                .font(.footnote)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task { await viewModel.deleteEntry(entry) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private var addBlockSection: some View {
        Section("Create Block") {
            DatePicker("Start", selection: $newBlockStart, displayedComponents: [.date, .hourAndMinute])
            DatePicker("End", selection: $newBlockEnd, displayedComponents: [.date, .hourAndMinute])
                .onChange(of: newBlockStart) { newValue in
                    if newBlockEnd <= newValue {
                        newBlockEnd = newValue.addingTimeInterval(3600)
                    }
                }
            if viewModel.rooms.isEmpty == false {
                Picker("Room", selection: Binding(
                    get: { newBlockRoomId ?? viewModel.rooms.first?.id ?? "" },
                    set: { newValue in newBlockRoomId = newValue }
                )) {
                    ForEach(viewModel.rooms) { room in
                        Text(room.name).tag(room.id)
                    }
                }
            }
            TextField("Internal note", text: $newBlockNote)
            Button("Add Block") {
                Task {
                    await viewModel.addBlock(start: newBlockStart, end: newBlockEnd, roomId: newBlockRoomId, note: newBlockNote)
                }
            }
            Button("Self-book this slot") {
                Task {
                    await viewModel.addSelfBooking(start: newBlockStart, end: newBlockEnd, roomId: newBlockRoomId, note: newBlockNote)
                }
            }
            .tint(.orange)
        }
    }

    private func weekdayName(for index: Int) -> String {
        let calendar = Calendar.current
        let weekdaySymbols = calendar.weekdaySymbols
        let normalized = (index % 7 + 7) % 7
        return weekdaySymbols[normalized]
    }

    private func hourLabel(for range: RecurringTimeRange) -> String {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: Date()).addingTimeInterval(TimeInterval(range.startTimeMinutes * 60))
        let endDate = startDate.addingTimeInterval(TimeInterval(range.durationMinutes * 60))
        return "\(startDate.formatted(date: .omitted, time: .shortened)) – \(endDate.formatted(date: .omitted, time: .shortened))"
    }

    private func formatted(date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func entryTitle(_ entry: AvailabilityEntry) -> String {
        switch entry.kind {
        case .block:
            return "Block"
        case .selfBooking:
            return "Self booking"
        case .bookingHold:
            return "Booking hold"
        case .recurring:
            return "Recurring"
        }
    }

    private func durationLabel(for minutes: Int) -> String {
        "\(minutes / 60)h"
    }
}
