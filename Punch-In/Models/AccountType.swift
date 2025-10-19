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
    case designer
    case videoVixen
    case journalist
    case anr

    static var allCases: [AccountType] {
        [
            .artist,
            .producer,
            .dj,
            .photographer,
            .videographer,
            .videoVixen,
            .journalist,
            .designer,
            .podcast,
            .engineer,
            .studioOwner,
            .eventCenter,
            .anr
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
        case contentStudioFormats
        case productionStyles
        case designerStyles
        case modelingSpecialties
        case journalistBeats
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
        case .podcast: return "Content Studio"
        case .designer: return "Designer"
        case .videoVixen: return "Model"
        case .journalist: return "Journalist"
        case .anr: return "A&R"
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
            return "Present your studio offerings and connect with creators."
        case .designer:
            return "Share your latest drops and invite bids on exclusive pieces."
        case .videoVixen:
            return "Spotlight your appearances and land new bookings."
        case .journalist:
            return "Showcase recent stories and request new interviews."
        case .anr:
            return "Discover emerging talent while keeping your scouting private."
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
            return ["Studio focus", "Session format"]
        case .designer:
            return ["Design specialties", "Collection highlight"]
        case .videoVixen:
            return ["Modeling specialties", "Recent appearance or client"]
        case .journalist:
            return ["Primary beat", "Recent feature or outlet"]
        case .anr:
            return ["Label or company", "Talent focus"]
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
        profileFieldStyle == .specialties && primaryOptionsCategory != nil
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
            return .contentStudioFormats
        case .engineer:
            return .genres
        case .designer:
            return .designerStyles
        case .videoVixen:
            return .modelingSpecialties
        case .journalist:
            return .journalistBeats
        case .studioOwner, .eventCenter, .anr:
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
            return "Select Studio Offerings"
        case .engineer:
            return "Select Specialties"
        case .designer:
            return "Select Design Styles"
        case .videoVixen:
            return "Select Modeling Specialties"
        case .journalist:
            return "Select Coverage Beats"
        case .studioOwner, .eventCenter, .anr:
            return "Select Options"
        }
    }

    var primaryOptionsLimit: Int {
        usesPrimaryOptions ? 3 : 0
    }

    var isArtistFamily: Bool {
        switch self {
        case .artist, .producer, .dj, .photographer, .videographer, .podcast, .designer, .videoVixen, .journalist:
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

    var requiresAgeVerification: Bool { self == .videoVixen }

    var isPrivateProfile: Bool { self == .anr }

    struct ContactAction {
        let cardTitle: String
        let cardIcon: String
        let buttonTitle: String
        let sheetTitle: String
        let sheetMessage: String
    }

    var contactAction: ContactAction? {
        switch self {
        case .dj:
            return ContactAction(
                cardTitle: "Book this DJ",
                cardIcon: "music.note",
                buttonTitle: "Book This DJ",
                sheetTitle: "Connect with this DJ",
                sheetMessage: "Share your event date, location, and vibe so they can confirm availability."
            )
        case .photographer:
            return ContactAction(
                cardTitle: "Book this Photographer",
                cardIcon: "camera.fill",
                buttonTitle: "Book This Photographer",
                sheetTitle: "Request a shoot",
                sheetMessage: "Provide shoot details like location, time, and creative direction."
            )
        case .videographer:
            return ContactAction(
                cardTitle: "Book this Videographer",
                cardIcon: "video.fill",
                buttonTitle: "Book This Videographer",
                sheetTitle: "Start a video project",
                sheetMessage: "Let them know the concept, timeline, and deliverables you're expecting."
            )
        case .eventCenter:
            return ContactAction(
                cardTitle: "Request this Venue",
                cardIcon: "building.2.fill",
                buttonTitle: "Request This Venue",
                sheetTitle: "Request a venue booking",
                sheetMessage: "Include your event size, preferred dates, and production needs."
            )
        case .podcast:
            return ContactAction(
                cardTitle: "Request this Content Studio",
                cardIcon: "mic.fill",
                buttonTitle: "Request This Content Studio",
                sheetTitle: "Request studio time",
                sheetMessage: "Share the type of content you're producing and when you'd like to record."
            )
        case .designer:
            return ContactAction(
                cardTitle: "Place a Bid",
                cardIcon: "tag.fill",
                buttonTitle: "Place a Bid",
                sheetTitle: "Bid on this collection",
                sheetMessage: "Send your offer, sizing, and any customization requests."
            )
        case .videoVixen:
            return ContactAction(
                cardTitle: "Request this Model",
                cardIcon: "sparkles",
                buttonTitle: "Request This Model",
                sheetTitle: "Request a booking",
                sheetMessage: "Share project details, shoot timing, and compensation to start the conversation."
            )
        case .journalist:
            return ContactAction(
                cardTitle: "Request coverage",
                cardIcon: "newspaper.fill",
                buttonTitle: "Request an Interview",
                sheetTitle: "Pitch your story",
                sheetMessage: "Provide your angle, timing, and any materials to help them prep."
            )
        default:
            return nil
        }
    }

    var heroBadgeSystemImage: String? {
        switch self {
        case .anr:
            return "seal.fill"
        default:
            return nil
        }
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
