import FirebaseStorage
import Foundation

/// Handles onboarding progress and temporary user input.
@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var username: String = ""
    @Published var selectedAccountType: AccountType = .artist {
        didSet {
            guard selectedAccountType != oldValue else { return }

            if selectedAccountType.profileFieldStyle == .location {
                if oldValue.profileFieldStyle != .location {
                    selectedPrimaryOptions = []
                    fieldOne = ""
                    fieldTwo = ""
                } else if selectedAccountType != oldValue {
                    fieldOne = ""
                    fieldTwo = ""
                }
            } else {
                if oldValue.profileFieldStyle == .location {
                    fieldTwo = ""
                }
                if selectedAccountType.primaryOptionsCategory != oldValue.primaryOptionsCategory {
                    selectedPrimaryOptions = []
                }
                syncPrimaryOptionsFromStoredValue()
            }

            if selectedAccountType.profileFieldStyle != .location && !selectedAccountType.usesPrimaryOptions {
                selectedPrimaryOptions = []
            }
        }
    }
    @Published var fieldOne: String = ""
    @Published var fieldTwo: String = ""
    @Published var publicBio: String = ""
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var didSave = false
    @Published var upcomingProjects: [ProfileSpotlight] = []
    @Published var upcomingEvents: [ProfileSpotlight] = []
    @Published var selectedPrimaryOptions: [String] = [] {
        didSet {
            if selectedAccountType.usesPrimaryOptions {
                fieldOne = selectedPrimaryOptions.joined(separator: ", ")
            }
        }
    }

    let maxSpotlightsPerCategory = 3

    private let appState: AppState
    private let firestoreService: any FirestoreService
    private let storageService: any StorageService
    let canEditAccountType: Bool

    init(appState: AppState, firestoreService: any FirestoreService, storageService: any StorageService) {
        self.appState = appState
        self.firestoreService = firestoreService
        self.storageService = storageService
        self.canEditAccountType = !appState.hasCompletedOnboarding

        if let profile = appState.currentUser {
            username = profile.username
            selectedAccountType = profile.accountType
            fieldOne = profile.profileDetails.fieldOne
            fieldTwo = profile.profileDetails.fieldTwo
            publicBio = profile.profileDetails.bio
            let now = Date()
            upcomingProjects = profile.profileDetails.upcomingProjects.sanitized(referenceDate: now)
            upcomingEvents = profile.profileDetails.upcomingEvents.sanitized(referenceDate: now)
        }

        syncPrimaryOptionsFromStoredValue()
    }

    var fieldOneLabel: String { selectedAccountType.requiredFieldLabels.first ?? "Details" }
    var fieldTwoLabel: String { selectedAccountType.requiredFieldLabels.last ?? "More details" }

    var isContinueEnabled: Bool {
        let trimmedUsername = username.trimmed
        let trimmedFieldTwo = fieldTwo.trimmed
        let trimmedBio = publicBio.trimmed
        switch selectedAccountType.profileFieldStyle {
        case .location:
            let trimmedFieldOne = fieldOne.trimmed
            return !trimmedUsername.isEmpty && !trimmedFieldOne.isEmpty && !trimmedFieldTwo.isEmpty && !trimmedBio.isEmpty
        case .specialties:
            return !trimmedUsername.isEmpty && !selectedPrimaryOptions.isEmpty && !trimmedFieldTwo.isEmpty && !trimmedBio.isEmpty
        }
    }

    func saveProfile(profileImageData: Data?, profileImageContentType: String, removeProfileImage: Bool) async {
        guard isContinueEnabled else { return }
        guard let existingProfile = appState.currentUser else { return }

        if let data = profileImageData, data.count >= 8 * 1024 * 1024 {
            errorMessage = "Profile image must be smaller than 8 MB."
            return
        }

        isSaving = true
        errorMessage = nil
        didSave = false

        let trimmedUsername = username.trimmed
        let primaryValue: String = selectedAccountType.usesPrimaryOptions
            ? selectedPrimaryOptions.joined(separator: ", ")
            : fieldOne.trimmed

        var updatedProfile = existingProfile
        updatedProfile.username = trimmedUsername
        updatedProfile.displayName = trimmedUsername
        updatedProfile.accountType = selectedAccountType
        updatedProfile.profileDetails = AccountProfileDetails(
            bio: publicBio.trimmed,
            fieldOne: primaryValue,
            fieldTwo: fieldTwo.trimmed,
            upcomingProjects: upcomingProjects.sanitized(),
            upcomingEvents: upcomingEvents.sanitized()
        )
        upcomingProjects = updatedProfile.profileDetails.upcomingProjects
        upcomingEvents = updatedProfile.profileDetails.upcomingEvents

        var resolvedProfileImageURL = existingProfile.profileImageURL

        if removeProfileImage {
            do {
                try await deleteFileIfExists(path: profileImagePath(for: existingProfile.id))
                resolvedProfileImageURL = nil
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
                return
            }
        } else if let data = profileImageData {
            do {
                resolvedProfileImageURL = try await storageService.uploadImage(
                    data: data,
                    path: profileImagePath(for: existingProfile.id),
                    contentType: profileImageContentType
                )
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
                return
            }
        }

        updatedProfile.profileImageURL = resolvedProfileImageURL

        do {
            try await firestoreService.saveUserProfile(updatedProfile)
            appState.currentUser = updatedProfile
            appState.hasCompletedOnboarding = true
            didSave = true
            Logger.log("Onboarding completed for username: \(updatedProfile.username) as \(updatedProfile.accountType.title)")
        } catch {
            errorMessage = error.localizedDescription
            Logger.log("Onboarding save failed: \(error.localizedDescription)")
        }

        isSaving = false
    }

    func setPrimaryOptions(_ options: [String]) {
        selectedPrimaryOptions = options
    }

    func setLocation(_ displayName: String) {
        fieldTwo = displayName
    }

    func primaryOptions(for accountType: AccountType) -> [String] {
        guard let category = accountType.primaryOptionsCategory else { return [] }
        switch category {
        case .genres:
            return ProfileOptions.genres
        case .djStyles:
            return ProfileOptions.djStyles
        case .photographySpecialties:
            return ProfileOptions.photographySpecialties
        case .videographySpecialties:
            return ProfileOptions.videographySpecialties
        case .podcastTopics:
            return ProfileOptions.podcastTopics
        case .productionStyles:
            return ProfileOptions.productionStyles
        }
    }

    func primaryOptionsLimit(for accountType: AccountType) -> Int {
        accountType.primaryOptionsLimit
    }

    private func syncPrimaryOptionsFromStoredValue() {
        guard selectedAccountType.usesPrimaryOptions else {
            selectedPrimaryOptions = []
            return
        }

        let tokens = fieldOne
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        selectedPrimaryOptions = tokens
    }

    private func deleteFileIfExists(path: String) async throws {
        do {
            try await storageService.deleteFile(at: path)
        } catch {
            if let storageError = error as NSError?,
               storageError.domain == StorageErrorDomain,
               StorageErrorCode(rawValue: storageError.code) == .objectNotFound {
                return
            }
            throw error
        }
    }

    private func profileImagePath(for userId: String) -> String {
        "users/\(userId)/profile/avatar.jpg"
    }

    func addSpotlight(for category: ProfileSpotlight.Category) {
        switch category {
        case .project:
            guard upcomingProjects.count < maxSpotlightsPerCategory else { return }
            upcomingProjects.append(ProfileSpotlight(category: .project))
        case .event:
            guard upcomingEvents.count < maxSpotlightsPerCategory else { return }
            upcomingEvents.append(ProfileSpotlight(category: .event, scheduledAt: Date()))
        }
    }

    func removeSpotlight(id: String, category: ProfileSpotlight.Category) {
        switch category {
        case .project:
            upcomingProjects.removeAll { $0.id == id }
        case .event:
            upcomingEvents.removeAll { $0.id == id }
        }
    }

    func canAddSpotlight(for category: ProfileSpotlight.Category) -> Bool {
        switch category {
        case .project:
            return upcomingProjects.count < maxSpotlightsPerCategory
        case .event:
            return upcomingEvents.count < maxSpotlightsPerCategory
        }
    }
}
