import Foundation

@MainActor
final class StudioAvailabilityManagementViewModel: ObservableObject {
    @Published var studio: Studio
    @Published var rooms: [Room] = []
    @Published var availabilityEntries: [AvailabilityEntry] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isPersisting = false
    @Published var persistMessage: String?

    private let firestore: any FirestoreService
    private let currentUserProvider: () -> UserProfile?

    init(
        studio: Studio,
        firestore: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?
    ) {
        self.studio = studio
        self.firestore = firestore
        self.currentUserProvider = currentUserProvider
    }

    func load() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let roomsTask = firestore.fetchRooms(for: studio.id)
            async let availabilityTask = firestore.fetchAvailability(scope: .studio, ownerId: studio.id)
            let fetchedRooms = try await roomsTask
            rooms = sortRooms(fetchedRooms)
            studio.rooms = rooms.isEmpty ? nil : rooms.count
            availabilityEntries = try await availabilityTask
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleAutoApprove() async {
        studio.autoApproveRequests.toggle()
        await persistStudioChanges(message: studio.autoApproveRequests ? "Instant booking enabled" : "Instant booking disabled")
    }

    func addRecurringHour(weekday: Int, startMinutes: Int, durationMinutes: Int) async {
        var schedule = studio.operatingSchedule
        schedule.recurringHours.append(
            RecurringTimeRange(
                weekday: weekday,
                startTimeMinutes: startMinutes,
                durationMinutes: durationMinutes
            )
        )
        studio.operatingSchedule = schedule
        await persistStudioChanges(message: "Hours updated")
    }

    func removeRecurringHour(rangeId: String) async {
        var schedule = studio.operatingSchedule
        schedule.recurringHours.removeAll { $0.id == rangeId }
        studio.operatingSchedule = schedule
        await persistStudioChanges(message: "Hours updated")
    }

    func addBlock(start: Date, end: Date, roomId: String?, note: String?) async {
        guard let currentUser = currentUserProvider() else { return }
        let duration = max(30, Int(end.timeIntervalSince(start) / 60))
        let entry = AvailabilityEntry(
            kind: .block,
            ownerId: studio.id,
            studioId: studio.id,
            roomId: roomId,
            engineerId: nil,
            durationMinutes: duration,
            startDate: start,
            endDate: end,
            sourceBookingId: nil,
            createdBy: currentUser.id,
            notes: note
        )
        do {
            try await firestore.upsertAvailability(scope: .studio, entry: entry)
            availabilityEntries.append(entry)
            persistMessage = "Block added"
        } catch {
            persistMessage = error.localizedDescription
        }
    }

    func addSelfBooking(start: Date, end: Date, roomId: String?, note: String?) async {
        guard let currentUser = currentUserProvider() else { return }
        let duration = max(30, Int(end.timeIntervalSince(start) / 60))
        let entry = AvailabilityEntry(
            kind: .selfBooking,
            ownerId: studio.id,
            studioId: studio.id,
            roomId: roomId,
            engineerId: nil,
            durationMinutes: duration,
            startDate: start,
            endDate: end,
            sourceBookingId: nil,
            createdBy: currentUser.id,
            notes: note
        )
        do {
            try await firestore.upsertAvailability(scope: .studio, entry: entry)
            availabilityEntries.append(entry)
            persistMessage = "Session added"
        } catch {
            persistMessage = error.localizedDescription
        }
    }

    func deleteEntry(_ entry: AvailabilityEntry) async {
        do {
            try await firestore.deleteAvailability(scope: .studio, ownerId: studio.id, entryId: entry.id)
            availabilityEntries.removeAll { $0.id == entry.id }
            persistMessage = "Entry removed"
        } catch {
            persistMessage = error.localizedDescription
        }
    }

    func saveRoom(
        id: String?,
        name: String,
        description: String,
        hourlyRate: Double?,
        capacity: Int?,
        amenities: [String]
    ) async -> String? {
        let trimmedName = name.trimmed
        guard trimmedName.isEmpty == false else {
            return "Room name is required."
        }

        let roomId = id ?? UUID().uuidString
        let existing = rooms.first { $0.id == roomId }
        let isDefault = existing?.isDefault ?? rooms.isEmpty

        let room = Room(
            id: roomId,
            studioId: studio.id,
            name: trimmedName,
            description: description.trimmed,
            hourlyRate: hourlyRate,
            capacity: capacity,
            amenities: amenities,
            isDefault: isDefault
        )

        do {
            try await firestore.upsertRoom(room)
            if let index = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[index] = room
            } else {
                rooms.append(room)
            }
            rooms = sortRooms(rooms)
            studio.rooms = rooms.isEmpty ? nil : rooms.count
            try await firestore.upsertStudio(studio)
            persistMessage = "Room saved"
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func deleteRoom(_ room: Room) async -> String? {
        do {
            try await firestore.deleteRoom(roomId: room.id, studioId: studio.id)
            rooms.removeAll { $0.id == room.id }

            if room.isDefault, let firstIndex = rooms.indices.first {
                var defaultRoom = rooms[firstIndex]
                defaultRoom.isDefault = true
                rooms[firstIndex] = defaultRoom
                try await firestore.upsertRoom(defaultRoom)
            }

            rooms = sortRooms(rooms)
            studio.rooms = rooms.isEmpty ? nil : rooms.count
            try await firestore.upsertStudio(studio)
            persistMessage = "Room deleted"
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func persistStudioChanges(message: String) async {
        guard isPersisting == false else { return }
        isPersisting = true
        defer { isPersisting = false }
        do {
            try await firestore.upsertStudio(studio)
            persistMessage = message
        } catch {
            persistMessage = error.localizedDescription
        }
    }

    private func sortRooms(_ rooms: [Room]) -> [Room] {
        rooms.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && rhs.isDefault == false
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
