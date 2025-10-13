import Foundation

enum AccountType: String, CaseIterable, Identifiable, Codable, Equatable {
    case studioOwner
    case engineer
    case artist
    case producer
    case dj
    case photographer
    case videographer
    case eventCenter
    case podcast

    static var allCases: [AccountType] {
        [
            .artist,
            .producer,
            .dj,
            .photographer,
            .videographer,
            .podcast,
            .engineer,
            .studioOwner,
            .eventCenter
        ]
    }

    enum ProfileFieldStyle {
        case location
        case specialties
    }

    enum PrimaryOptionsCategory {
        case genres
        case djStyles
        case photographySpecialties
        case videographySpecialties
        case podcastTopics
        case productionStyles
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studioOwner: return "Studio Owner"
        case .engineer: return "Engineer"
        case .artist: return "Artist"
        case .producer: return "Producer"
        case .dj: return "DJ"
        case .photographer: return "Photographer"
        case .videographer: return "Videographer"
        case .eventCenter: return "Live Event Center"
        case .podcast: return "Podcast"
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
        case .producer:
            return "Share your beats, placements, and collaborate with artists."
        case .dj:
            return "Highlight your sets and get booked for events and residencies."
        case .photographer:
            return "Showcase your shoots and link up with artists and studios."
        case .videographer:
            return "Promote your video work and capture new productions."
        case .eventCenter:
            return "Promote your venue, list upcoming shows, and gather RSVPs."
        case .podcast:
            return "Present your show lineup and connect with new listeners."
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
        case .producer:
            return ["Production style", "Highlights or credits"]
        case .dj:
            return ["Primary style", "Residency or availability"]
        case .photographer:
            return ["Specialty focus", "Notable work or market"]
        case .videographer:
            return ["Primary format", "Signature project or clients"]
        case .eventCenter:
            return ["Venue name", "Venue location"]
        case .podcast:
            return ["Show topics", "Format or cadence"]
        }
    }

    var profileFieldStyle: ProfileFieldStyle {
        switch self {
        case .studioOwner, .eventCenter:
            return .location
        default:
            return .specialties
        }
    }

    var usesPrimaryOptions: Bool {
        profileFieldStyle == .specialties
    }

    var primaryOptionsCategory: PrimaryOptionsCategory? {
        switch self {
        case .artist:
            return .genres
        case .producer:
            return .productionStyles
        case .dj:
            return .djStyles
        case .photographer:
            return .photographySpecialties
        case .videographer:
            return .videographySpecialties
        case .podcast:
            return .podcastTopics
        case .engineer:
            return .genres
        case .studioOwner, .eventCenter:
            return nil
        }
    }

    var primaryOptionsTitle: String {
        switch self {
        case .artist:
            return "Select Genres"
        case .producer:
            return "Select Production Styles"
        case .dj:
            return "Select DJ Styles"
        case .photographer:
            return "Select Photography Specialties"
        case .videographer:
            return "Select Videography Specialties"
        case .podcast:
            return "Select Show Topics"
        case .engineer:
            return "Select Specialties"
        case .studioOwner, .eventCenter:
            return "Select Options"
        }
    }

    var primaryOptionsLimit: Int {
        usesPrimaryOptions ? 3 : 0
    }

    var isArtistFamily: Bool {
        switch self {
        case .artist, .producer, .dj, .photographer, .videographer, .podcast:
            return true
        default:
            return false
        }
    }

    var isEngineer: Bool { self == .engineer }

    var isStudioOwner: Bool { self == .studioOwner }

    var isLocationBased: Bool { profileFieldStyle == .location }

    var canViewStudioOwnerTools: Bool { self == .studioOwner }

    var canInitiateBookings: Bool {
        isArtistFamily || self == .eventCenter
    }
}

extension AccountType {
    var mediaCapabilities: ProfileMediaCapabilities {
        ProfileMediaCapabilities.forAccountType(self)
    }

    var supportsProfileMediaLibrary: Bool {
        !mediaCapabilities.allowedFormats.isEmpty
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
