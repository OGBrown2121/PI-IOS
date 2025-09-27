import Foundation

struct UserProfile: Identifiable, Equatable, Codable {
    let id: String
    var username: String
    var displayName: String
    let createdAt: Date
    var profileImageURL: URL?
    var accountType: AccountType
    var profileDetails: AccountProfileDetails

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
            fieldTwo: "Songwriter & vocalist"
        )
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
            fieldTwo: "Worked on 3 Top 40 releases"
        )
    )
}
