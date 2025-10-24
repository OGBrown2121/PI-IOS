import Foundation

@MainActor
final class VideographerBookingSettingsViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile
    @Published var defaultDurationSelection: Int?
    @Published var locationNote: String
    @Published var budgetNote: String
    @Published var projectTemplate: String
    @Published var gearRequirements: String
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var isSaving = false

    let durationOptions: [Int]

    private let firestore: any FirestoreService
    private let currentUserProvider: () -> UserProfile?
    private let onProfileUpdate: (UserProfile) -> Void
    private var originalSettings: VideographerSettings
    private var isApplyingSavedValues = false

    init(
        profile: UserProfile,
        firestore: any FirestoreService,
        currentUserProvider: @escaping () -> UserProfile?,
        onProfileUpdate: @escaping (UserProfile) -> Void
    ) {
        self.profile = profile
        self.firestore = firestore
        self.currentUserProvider = currentUserProvider
        self.onProfileUpdate = onProfileUpdate

        let settings = profile.videographerSettings
        self.originalSettings = settings
        self.defaultDurationSelection = settings.defaultProductionLengthMinutes
        self.locationNote = settings.defaultLocationNote
        self.budgetNote = settings.defaultBudgetNote
        self.projectTemplate = settings.projectDetailsTemplate
        self.gearRequirements = settings.gearRequirements

        if let options = profile.accountType.contactAction?.bookingFlow.durationOptions {
            self.durationOptions = options
        } else {
            self.durationOptions = [120, 180, 240, 360]
        }
    }

    var hasChanges: Bool {
        sanitizedSettings() != originalSettings
    }

    var canSave: Bool {
        hasChanges && isSaving == false
    }

    var canClear: Bool {
        (originalSettings.hasCustomizations || sanitizedSettings().hasCustomizations) && isSaving == false
    }

    func save() async {
        clearTransientMessages()
        guard hasChanges else {
            statusMessage = "No changes to save."
            return
        }
        await persist(settings: sanitizedSettings())
    }

    func clearAll() async {
        clearTransientMessages()
        guard originalSettings.hasCustomizations || sanitizedSettings().hasCustomizations else {
            statusMessage = "No defaults to clear."
            return
        }
        defaultDurationSelection = nil
        locationNote = ""
        budgetNote = ""
        projectTemplate = ""
        gearRequirements = ""
        await persist(settings: VideographerSettings())
    }

    func clearTransientMessages() {
        guard isApplyingSavedValues == false else { return }
        statusMessage = nil
        errorMessage = nil
    }

    private func sanitizedSettings() -> VideographerSettings {
        VideographerSettings(
            defaultProductionLengthMinutes: defaultDurationSelection,
            defaultLocationNote: locationNote.trimmed,
            defaultBudgetNote: budgetNote.trimmed,
            projectDetailsTemplate: projectTemplate.trimmed,
            gearRequirements: gearRequirements.trimmed
        )
    }

    private func persist(settings: VideographerSettings) async {
        isSaving = true
        statusMessage = nil
        errorMessage = nil
        defer { isSaving = false }

        guard var currentProfile = currentUserProvider() else {
            errorMessage = "You need to be signed in to update preferences."
            return
        }

        currentProfile.videographerSettings = settings

        do {
            try await firestore.saveUserProfile(currentProfile)
            profile = currentProfile
            originalSettings = settings
            isApplyingSavedValues = true
            defaultDurationSelection = settings.defaultProductionLengthMinutes
            locationNote = settings.defaultLocationNote
            budgetNote = settings.defaultBudgetNote
            projectTemplate = settings.projectDetailsTemplate
            gearRequirements = settings.gearRequirements
            isApplyingSavedValues = false
            statusMessage = settings.hasCustomizations
                ? "Booking defaults updated."
                : "Booking defaults cleared."
            onProfileUpdate(currentProfile)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
