import Foundation

struct UserProfile: Identifiable, Equatable, Codable {
    enum DrivePlan: String, CaseIterable, Identifiable, Codable {
        case free
        case subscribed

        var id: String { rawValue }

        var storageLimitBytes: Int {
            switch self {
            case .free:
                return 3 * 1024 * 1024 * 1024
            case .subscribed:
                return 10 * 1024 * 1024 * 1024
            }
        }

        var displayName: String {
            switch self {
            case .free:
                return "Free"
            case .subscribed:
                return "Subscribed"
            }
        }

        var storageDescription: String {
            switch self {
            case .free:
                return "Includes 3 GB of project storage"
            case .subscribed:
                return "Includes 10 GB of project storage"
            }
        }
    }

    let id: String
    var username: String
    var displayName: String
    let createdAt: Date
    var profileImageURL: URL?
    var accountType: AccountType
    var profileDetails: AccountProfileDetails
    var contact: UserContactInfo
    var engineerSettings: EngineerSettings
    var videographerSettings: VideographerSettings
    var drivePlan: DrivePlan = .free

    var mediaCapabilities: ProfileMediaCapabilities {
        accountType.mediaCapabilities
    }

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
        merged.videographerSettings = remote.videographerSettings
        merged.drivePlan = remote.drivePlan
        return merged
    }

    var driveStorageLimitBytes: Int {
        drivePlan.storageLimitBytes
    }

    var hasDriveStorageAccess: Bool {
        driveStorageLimitBytes > 0
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
        engineerSettings: EngineerSettings(),
        videographerSettings: VideographerSettings(),
        drivePlan: .subscribed
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
        engineerSettings: EngineerSettings(isPremium: true, instantBookEnabled: true),
        videographerSettings: VideographerSettings(),
        drivePlan: .subscribed
    )

    static let previewProducer = UserProfile(
        id: UUID().uuidString,
        username: "beatcraft",
        displayName: "Beatcraft Labs",
        createdAt: Date(),
        profileImageURL: nil,
        accountType: .producer,
        profileDetails: AccountProfileDetails(
            bio: "Producer blending analog synths with modern trap drums.",
            fieldOne: "Trap & R&B",
            fieldTwo: "Credits with indie breakout artists",
            upcomingProjects: [
                ProfileSpotlight(
                    category: .project,
                    title: "Beat tape \"Night Signals\"",
                    detail: "A curated pack of late-night instrumentals for vocalists and rappers.",
                    scheduledAt: Calendar.current.date(byAdding: .month, value: 1, to: Date())
                )
            ],
            upcomingEvents: []
        ),
        contact: UserContactInfo(email: "beats@beatcraft.com", phoneNumber: "555-0112"),
        engineerSettings: EngineerSettings(),
        videographerSettings: VideographerSettings(),
        drivePlan: .subscribed
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

struct VideographerSettings: Codable, Equatable {
    var defaultProductionLengthMinutes: Int?
    var defaultLocationNote: String
    var defaultBudgetNote: String
    var projectDetailsTemplate: String
    var gearRequirements: String

    init(
        defaultProductionLengthMinutes: Int? = nil,
        defaultLocationNote: String = "",
        defaultBudgetNote: String = "",
        projectDetailsTemplate: String = "",
        gearRequirements: String = ""
    ) {
        self.defaultProductionLengthMinutes = defaultProductionLengthMinutes
        self.defaultLocationNote = defaultLocationNote
        self.defaultBudgetNote = defaultBudgetNote
        self.projectDetailsTemplate = projectDetailsTemplate
        self.gearRequirements = gearRequirements
    }

    var hasCustomizations: Bool {
        defaultProductionLengthMinutes != nil
            || !defaultLocationNote.trimmed.isEmpty
            || !defaultBudgetNote.trimmed.isEmpty
            || !projectDetailsTemplate.trimmed.isEmpty
            || !gearRequirements.trimmed.isEmpty
    }
}
