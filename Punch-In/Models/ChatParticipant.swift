import Foundation

struct ChatParticipant: Identifiable, Equatable, Hashable {
    enum Kind: Equatable {
        case user(UserProfile)
        case studio(Studio)
    }

    let id: String
    var kind: Kind

    init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    init(user: UserProfile) {
        self.init(id: user.id, kind: .user(user))
    }

    init(studio: Studio) {
        self.init(id: studio.id, kind: .studio(studio))
    }

    var displayName: String {
        switch kind {
        case let .user(profile):
            return profile.displayName.isEmpty ? profile.username : profile.displayName
        case let .studio(studio):
            return studio.name
        }
    }

    var secondaryText: String? {
        switch kind {
        case let .user(profile):
            if !profile.username.isEmpty {
                return "@\(profile.username)"
            }
            return nil
        case let .studio(studio):
            return studio.city.isEmpty ? nil : studio.city
        }
    }

    var avatarURL: URL? {
        switch kind {
        case let .user(profile):
            return profile.profileImageURL
        case let .studio(studio):
            return studio.logoImageURL ?? studio.coverImageURL
        }
    }

    var ownerId: String? {
        switch kind {
        case let .user(profile):
            return profile.id
        case let .studio(studio):
            return studio.ownerId
        }
    }

    var searchableKeywords: [String] {
        switch kind {
        case let .user(profile):
            let showcaseKeywords = (
                profile.profileDetails.upcomingProjects + profile.profileDetails.upcomingEvents
            ).flatMap { item -> [String] in
                [
                    item.title,
                    item.detail,
                    item.location
                ]
            }
            return [profile.displayName, profile.username, profile.profileDetails.bio, profile.profileDetails.fieldOne, profile.profileDetails.fieldTwo] + showcaseKeywords
        case let .studio(studio):
            return [studio.name, studio.city, studio.address] + studio.amenities
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ChatParticipant {
    static var sampleUsers: [ChatParticipant] { [
        .init(user: .mock),
        .init(user: .mockEngineer),
        .init(user: .mockProducer),
        .init(user: .mockWriter)
    ] }

    static var sampleStudios: [ChatParticipant] {
        Studio.mockList.map(ChatParticipant.init(studio:))
    }

    static var sampleAll: [ChatParticipant] {
        sampleUsers + sampleStudios
    }
}

private extension UserProfile {
    static let mockProducer = UserProfile(
        id: UUID().uuidString,
        username: "beatlab",
        displayName: "Aria Chen",
        createdAt: Date(),
        profileImageURL: nil,
        accountType: .artist,
        profileDetails: AccountProfileDetails(
            bio: "Producer blending electronic and R&B textures.",
            fieldOne: "Producer",
            fieldTwo: "Ableton, modular synths"
        ),
        contact: UserContactInfo(),
        engineerSettings: EngineerSettings(),
        drivePlan: .subscribed
    )

    static let mockWriter = UserProfile(
        id: UUID().uuidString,
        username: "hooksmith",
        displayName: "Omar Patel",
        createdAt: Date(),
        profileImageURL: nil,
        accountType: .artist,
        profileDetails: AccountProfileDetails(
            bio: "Songwriter crafting melodic hooks.",
            fieldOne: "Songwriter",
            fieldTwo: "Toplining"
        ),
        contact: UserContactInfo(),
        engineerSettings: EngineerSettings(),
        drivePlan: .subscribed
    )
}
