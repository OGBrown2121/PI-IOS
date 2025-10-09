import Foundation

enum AccountType: String, CaseIterable, Identifiable, Codable, Equatable {
    case studioOwner
    case engineer
    case artist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studioOwner: return "Studio Owner"
        case .engineer: return "Engineer"
        case .artist: return "Artist"
        }
    }

    var subtitle: String {
        switch self {
        case .studioOwner:
            return "List your studio for artists to discover and book."
        case .engineer:
            return "Connect with studios and showcase your engineering skills."
        case .artist:
            return "Find the right studio and collaborators for your sessions."
        }
    }

    var requiredFieldLabels: [String] {
        switch self {
        case .studioOwner:
            return ["Studio name", "Studio location"]
        case .engineer:
            return ["Specialty", "Experience highlight"]
        case .artist:
            return ["Primary genre", "Creative focus"]
        }
    }
}

struct AccountProfileDetails: Codable, Equatable {
    var bio: String = ""
    var fieldOne: String = ""
    var fieldTwo: String = ""
    var upcomingProjects: [ProfileSpotlight] = []
    var upcomingEvents: [ProfileSpotlight] = []

    var isComplete: Bool {
        !bio.trimmed.isEmpty && !fieldOne.trimmed.isEmpty && !fieldTwo.trimmed.isEmpty
    }
}
