import Foundation

@MainActor
final class EngineerAvailabilityManagementViewModel: ObservableObject {
    @Published var engineer: UserProfile
    @Published var availabilityEntries: [AvailabilityEntry] = []
    @Published var linkedStudios: [Studio] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let firestore: any FirestoreService
    private let currentUserProvider: () -> UserProfile?
    private let onProfileUpdate: (UserProfile) -> Void

    init(
        engineer: UserProfile,
        firestore: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?,
        onProfileUpdate: @escaping (UserProfile) -> Void
    ) {
        self.engineer = engineer
        self.firestore = firestore
        self.currentUserProvider = currentUserProvider
        self.onProfileUpdate = onProfileUpdate
    }

    func load() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let availabilityTask = firestore.fetchAvailability(scope: .engineer, ownerId: engineer.id)
            async let studiosTask = firestore.fetchStudios()
            availabilityEntries = try await availabilityTask
            let studios = try await studiosTask
            linkedStudios = studios.filter { $0.approvedEngineerIds.contains(engineer.id) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func togglePremium(_ isOn: Bool) async {
        engineer.engineerSettings.isPremium = isOn
        if isOn == false {
            engineer.engineerSettings.instantBookEnabled = false
        }
        await persistProfile(message: "Premium updated")
    }

    func setEngineerRequiresApproval(_ requiresApproval: Bool) async {
        if requiresApproval {
            engineer.engineerSettings.instantBookEnabled = false
            await persistProfile(message: "Engineer approval required")
            return
        }

        guard engineer.engineerSettings.isPremium else {
            statusMessage = "Enable the premium plan to auto-approve sessions."
            return
        }

        engineer.engineerSettings.instantBookEnabled = true
        await persistProfile(message: "Engineer auto-approval enabled")
    }

    func toggleAllowOtherStudios(_ isOn: Bool) async {
        engineer.engineerSettings.allowOtherStudios = isOn
        await persistProfile(message: "Availability updated")
    }

    func setMainStudio(_ studioId: String?) async {
        engineer.engineerSettings.mainStudioId = studioId
        engineer.engineerSettings.mainStudioSelectedAt = Date()
        await persistProfile(message: studioId == nil ? "Main studio cleared" : "Main studio set")
    }

    func addBlock(start: Date, end: Date, note: String?) async {
        guard let currentUser = currentUserProvider() else { return }
        let duration = max(30, Int(end.timeIntervalSince(start) / 60))
        let entry = AvailabilityEntry(
            kind: .block,
            ownerId: engineer.id,
            studioId: engineer.engineerSettings.mainStudioId,
            roomId: nil,
            engineerId: engineer.id,
            durationMinutes: duration,
            startDate: start,
            endDate: end,
            sourceBookingId: nil,
            createdBy: currentUser.id,
            notes: note
        )
        do {
            try await firestore.upsertAvailability(scope: .engineer, entry: entry)
            availabilityEntries.append(entry)
            statusMessage = "Block added"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func addSelfBooking(start: Date, end: Date, note: String?) async {
        guard let currentUser = currentUserProvider() else { return }
        let duration = max(30, Int(end.timeIntervalSince(start) / 60))
        let entry = AvailabilityEntry(
            kind: .selfBooking,
            ownerId: engineer.id,
            studioId: engineer.engineerSettings.mainStudioId,
            roomId: nil,
            engineerId: engineer.id,
            durationMinutes: duration,
            startDate: start,
            endDate: end,
            sourceBookingId: nil,
            createdBy: currentUser.id,
            notes: note
        )
        do {
            try await firestore.upsertAvailability(scope: .engineer, entry: entry)
            availabilityEntries.append(entry)
            statusMessage = "Session added"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func deleteEntry(_ entry: AvailabilityEntry) async {
        do {
            try await firestore.deleteAvailability(scope: .engineer, ownerId: engineer.id, entryId: entry.id)
            availabilityEntries.removeAll { $0.id == entry.id }
            statusMessage = "Entry removed"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func persistProfile(message: String) async {
        do {
            try await firestore.saveUserProfile(engineer)
            onProfileUpdate(engineer)
            statusMessage = message
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
