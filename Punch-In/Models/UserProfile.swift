import Foundation

struct UserProfile: Identifiable, Equatable, Codable {
    let id: String
    var username: String
    var displayName: String
    let createdAt: Date
    var profileImageURL: URL?
    var accountType: AccountType
    var profileDetails: AccountProfileDetails
    var contact: UserContactInfo
    var engineerSettings: EngineerSettings

    var hasCompletedOnboarding: Bool {
        profileDetails.isComplete
    }

    func merging(with remote: UserProfile?) -> UserProfile {
        guard let remote else { return self }
        var merged = remote
        merged.displayName = remote.displayName.isEmpty ? displayName : remote.displayName
        merged.username = remote.username.isEmpty ? username : remote.username
        merged.accountType = remote.accountType
        merged.profileDetails = remote.profileDetails
        if merged.profileImageURL == nil {
            merged.profileImageURL = profileImageURL
        }
        merged.contact = remote.contact
        merged.engineerSettings = remote.engineerSettings
        return merged
    }
}

extension UserProfile {
    static let mock = UserProfile(
        id: UUID().uuidString,
        username: "studiofan",
        displayName: "Studio Fan",
        createdAt: Date(),
        profileImageURL: nil,
        accountType: .artist,
        profileDetails: AccountProfileDetails(
            bio: "Bedroom producer exploring new sounds",
            fieldOne: "Indie Pop",
            fieldTwo: "Songwriter & vocalist",
            upcomingProjects: [
                ProfileSpotlight(
                    category: .project,
                    title: "Debut EP \"Neon Nights\"",
                    detail: "Collaborating with local artists to craft a 5-song release blending synth-pop and indie vibes.",
                    scheduledAt: Calendar.current.date(byAdding: .month, value: 1, to: Date()),
                    callToActionTitle: "Pre-save",
                    callToActionURL: URL(string: "https://example.com/presave")
                )
            ],
            upcomingEvents: [
                ProfileSpotlight(
                    category: .event,
                    title: "Live listening party",
                    detail: "A cozy studio session previewing the new EP with Q&A and merch.",
                    scheduledAt: Calendar.current.date(byAdding: .day, value: 14, to: Date()),
                    location: "Brooklyn, NY",
                    callToActionTitle: "RSVP",
                    callToActionURL: URL(string: "https://example.com/rsvp")
                )
            ]
        ),
        contact: UserContactInfo(),
        engineerSettings: EngineerSettings()
    )

    static let mockEngineer = UserProfile(
        id: UUID().uuidString,
        username: "mixmaster",
        displayName: "Jamie Rivera",
        createdAt: Date(),
        profileImageURL: nil,
        accountType: .engineer,
        profileDetails: AccountProfileDetails(
            bio: "Mixing live instrumentation with contemporary pop textures.",
            fieldOne: "Mixing & Mastering",
            fieldTwo: "Worked on 3 Top 40 releases",
            upcomingProjects: [
                ProfileSpotlight(
                    category: .project,
                    title: "Summer festival live mix",
                    detail: "Leading FOH mix prep for three touring acts ahead of the Skyline Festival.",
                    scheduledAt: Calendar.current.date(byAdding: .month, value: 2, to: Date())
                )
            ],
            upcomingEvents: [
                ProfileSpotlight(
                    category: .event,
                    title: "Mixing masterclass",
                    detail: "Hands-on workshop at Circuit Studios covering hybrid mixing workflows.",
                    scheduledAt: Calendar.current.date(byAdding: .day, value: 21, to: Date()),
                    location: "Los Angeles, CA",
                    callToActionTitle: "Join waitlist",
                    callToActionURL: URL(string: "https://example.com/masterclass")
                )
            ]
        ),
        contact: UserContactInfo(email: "jamie@example.com", phoneNumber: "555-0102"),
        engineerSettings: EngineerSettings(isPremium: true, instantBookEnabled: true)
    )
}

struct UserContactInfo: Codable, Equatable {
    var email: String
    var phoneNumber: String

    init(email: String = "", phoneNumber: String = "") {
        self.email = email
        self.phoneNumber = phoneNumber
    }
}

struct EngineerSettings: Codable, Equatable {
    var isPremium: Bool
    var instantBookEnabled: Bool
    var mainStudioId: String?
    var allowOtherStudios: Bool
    var mainStudioSelectedAt: Date?
    var defaultSessionDurationMinutes: Int

    init(
        isPremium: Bool = false,
        instantBookEnabled: Bool = false,
        mainStudioId: String? = nil,
        allowOtherStudios: Bool = false,
        mainStudioSelectedAt: Date? = nil,
        defaultSessionDurationMinutes: Int = 120
    ) {
        self.isPremium = isPremium
        self.instantBookEnabled = instantBookEnabled
        self.mainStudioId = mainStudioId
        self.allowOtherStudios = allowOtherStudios
        self.mainStudioSelectedAt = mainStudioSelectedAt
        self.defaultSessionDurationMinutes = defaultSessionDurationMinutes
    }

    var canInstantBook: Bool {
        isPremium && instantBookEnabled
    }
}
