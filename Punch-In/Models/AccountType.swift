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
        struct BookingFlowConfiguration {
            let requestTitle: String
            let requestDescription: String
            let includesSchedule: Bool
            let durationLabel: String
            let durationOptions: [Int]
            let defaultDurationMinutes: Int
            let includesLocation: Bool
            let locationLabel: String
            let includesBudget: Bool
            let budgetLabel: String
            let notesPlaceholder: String
            let submitButtonTitle: String
            let emailSubject: String

            init(
                requestTitle: String,
                requestDescription: String,
                includesSchedule: Bool = true,
                durationLabel: String,
                durationOptions: [Int],
                defaultDurationMinutes: Int,
                includesLocation: Bool,
                locationLabel: String,
                includesBudget: Bool,
                budgetLabel: String,
                notesPlaceholder: String,
                submitButtonTitle: String,
                emailSubject: String
            ) {
                self.requestTitle = requestTitle
                self.requestDescription = requestDescription
                self.includesSchedule = includesSchedule
                self.durationLabel = durationLabel
                self.durationOptions = durationOptions
                self.defaultDurationMinutes = defaultDurationMinutes
                self.includesLocation = includesLocation
                self.locationLabel = locationLabel
                self.includesBudget = includesBudget
                self.budgetLabel = budgetLabel
                self.notesPlaceholder = notesPlaceholder
                self.submitButtonTitle = submitButtonTitle
                self.emailSubject = emailSubject
            }
        }
        let cardTitle: String
        let cardIcon: String
        let buttonTitle: String
        let sheetTitle: String
        let sheetMessage: String
        let bookingFlow: BookingFlowConfiguration
    }

    var contactAction: ContactAction? {
        switch self {
        case .dj:
            return ContactAction(
                cardTitle: "Book this DJ",
                cardIcon: "music.note",
                buttonTitle: "Book This DJ",
                sheetTitle: "DJ Booking",
                sheetMessage: "Share your event date, location, and vibe so they can confirm availability.",
                bookingFlow: .init(
                    requestTitle: "DJ Booking",
                    requestDescription: "Lock in your DJ by outlining the event details, length of the set, and the vibe you're aiming for.",
                    durationLabel: "Set length",
                    durationOptions: [60, 90, 120, 180],
                    defaultDurationMinutes: 120,
                    includesLocation: true,
                    locationLabel: "Event location",
                    includesBudget: true,
                    budgetLabel: "Budget (optional)",
                    notesPlaceholder: "Share the crowd size, preferred genres, equipment on site, and any must-play moments.",
                    submitButtonTitle: "Send DJ Request",
                    emailSubject: "DJ Booking Request"
                )
            )
        case .photographer:
            return ContactAction(
                cardTitle: "Book this Photographer",
                cardIcon: "camera.fill",
                buttonTitle: "Book This Photographer",
                sheetTitle: "Photo Shoot",
                sheetMessage: "Provide shoot details like location, time, and creative direction.",
                bookingFlow: .init(
                    requestTitle: "Photo Shoot Request",
                    requestDescription: "Outline the shoot concept, timing, and deliverables so they can prep the right gear.",
                    durationLabel: "Shoot length",
                    durationOptions: [60, 90, 120, 180],
                    defaultDurationMinutes: 120,
                    includesLocation: true,
                    locationLabel: "Shoot location",
                    includesBudget: true,
                    budgetLabel: "Budget (optional)",
                    notesPlaceholder: "Share inspiration, shot list ideas, wardrobe plans, and delivery expectations.",
                    submitButtonTitle: "Send Shoot Request",
                    emailSubject: "Photography Booking Request"
                )
            )
        case .videographer:
            return ContactAction(
                cardTitle: "Book this Videographer",
                cardIcon: "video.fill",
                buttonTitle: "Book This Videographer",
                sheetTitle: "Video Project",
                sheetMessage: "Let them know the concept, timeline, and deliverables you're expecting.",
                bookingFlow: .init(
                    requestTitle: "Video Project Request",
                    requestDescription: "Share the concept, production timing, and final deliverables to kick off the project.",
                    durationLabel: "Production length",
                    durationOptions: [120, 180, 240, 360],
                    defaultDurationMinutes: 240,
                    includesLocation: true,
                    locationLabel: "Shoot locations",
                    includesBudget: false,
                    budgetLabel: "",
                    notesPlaceholder: "Describe the storyline, references, crew needs, and post-production expectations.",
                    submitButtonTitle: "Send Video Request",
                    emailSubject: "Videography Booking Request"
                )
            )
        case .eventCenter:
            return ContactAction(
                cardTitle: "Request this Venue",
                cardIcon: "building.2.fill",
                buttonTitle: "Request This Venue",
                sheetTitle: "Venue Request",
                sheetMessage: "Include your event size, preferred dates, and production needs.",
                bookingFlow: .init(
                    requestTitle: "Venue Booking Request",
                    requestDescription: "Map out the event timing, production needs, and audience size so the venue can confirm availability.",
                    durationLabel: "Event duration",
                    durationOptions: [180, 240, 360, 480],
                    defaultDurationMinutes: 240,
                    includesLocation: false,
                    locationLabel: "",
                    includesBudget: true,
                    budgetLabel: "Budget (optional)",
                    notesPlaceholder: "Share load-in requirements, production needs, and any special requests.",
                    submitButtonTitle: "Send Venue Request",
                    emailSubject: "Venue Booking Request"
                )
            )
        case .podcast:
            return ContactAction(
                cardTitle: "Request this Content Studio",
                cardIcon: "mic.fill",
                buttonTitle: "Request This Content Studio",
                sheetTitle: "Studio Request",
                sheetMessage: "Share the type of content you're producing and when you'd like to record.",
                bookingFlow: .init(
                    requestTitle: "Studio Session Request",
                    requestDescription: "Let them know the format, session timing, and equipment needs for your content.",
                    durationLabel: "Session length",
                    durationOptions: [60, 90, 120, 180],
                    defaultDurationMinutes: 120,
                    includesLocation: false,
                    locationLabel: "",
                    includesBudget: true,
                    budgetLabel: "Budget (optional)",
                    notesPlaceholder: "List your show format, crew size, and any gear or set needs.",
                    submitButtonTitle: "Send Studio Request",
                    emailSubject: "Content Studio Booking Request"
                )
            )
        case .designer:
            return ContactAction(
                cardTitle: "Place a Bid",
                cardIcon: "tag.fill",
                buttonTitle: "Place a Bid",
                sheetTitle: "Collection Request",
                sheetMessage: "Send your offer, sizing, and any customization requests.",
                bookingFlow: .init(
                    requestTitle: "Design Bid",
                    requestDescription: "Outline your desired pieces, sizing, and turnaround to receive an accurate quote.",
                    includesSchedule: false,
                    durationLabel: "Consultation length",
                    durationOptions: [30, 45, 60],
                    defaultDurationMinutes: 45,
                    includesLocation: false,
                    locationLabel: "",
                    includesBudget: true,
                    budgetLabel: "Offer amount",
                    notesPlaceholder: "Share measurements, fabric preferences, customization ideas, and delivery expectations.",
                    submitButtonTitle: "Send Bid",
                    emailSubject: "Design Bid Request"
                )
            )
        case .videoVixen:
            return ContactAction(
                cardTitle: "Request this Model",
                cardIcon: "sparkles",
                buttonTitle: "Request This Model",
                sheetTitle: "Model Booking",
                sheetMessage: "Share project details, shoot timing, and compensation to start the conversation.",
                bookingFlow: .init(
                    requestTitle: "Model Booking Request",
                    requestDescription: "Provide shoot dates, project concept, and usage details so they can confirm.",
                    durationLabel: "Booking length",
                    durationOptions: [60, 90, 120, 180],
                    defaultDurationMinutes: 120,
                    includesLocation: true,
                    locationLabel: "Shoot location",
                    includesBudget: true,
                    budgetLabel: "Compensation offer",
                    notesPlaceholder: "Include wardrobe expectations, concept references, and release details.",
                    submitButtonTitle: "Send Booking Request",
                    emailSubject: "Model Booking Request"
                )
            )
        case .journalist:
            return ContactAction(
                cardTitle: "Request coverage",
                cardIcon: "newspaper.fill",
                buttonTitle: "Request an Interview",
                sheetTitle: "Interview Request",
                sheetMessage: "Provide your angle, timing, and any materials to help them prep.",
                bookingFlow: .init(
                    requestTitle: "Interview Request",
                    requestDescription: "Share your story angle, preferred timing, and supporting materials.",
                    durationLabel: "Interview length",
                    durationOptions: [30, 45, 60, 90],
                    defaultDurationMinutes: 45,
                    includesLocation: true,
                    locationLabel: "Interview location or link",
                    includesBudget: false,
                    budgetLabel: "",
                    notesPlaceholder: "Outline the interview format, outlet, publication date, and any talking points.",
                    submitButtonTitle: "Send Interview Request",
                    emailSubject: "Interview Request"
                )
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
