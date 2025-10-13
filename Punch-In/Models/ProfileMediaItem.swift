import Foundation

/// Represents a single piece of uploaded media that appears on a user's public profile.
struct ProfileMediaItem: Identifiable, Equatable, Codable {
    var id: String
    var ownerId: String
    var title: String
    var caption: String
    var format: ProfileMediaFormat
    var category: ProfileMediaCategory
    var mediaURL: URL?
    var thumbnailURL: URL?
    var coverArtURL: URL?
    var durationSeconds: Double?
    var fileSizeBytes: Int?
    var collaborators: [ProfileMediaCollaborator]
    var playCount: Int = 0
    var ratings: [String: Int]
    var pinnedRank: Int?
    var isShared: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        ownerId: String,
        title: String,
        caption: String = "",
        format: ProfileMediaFormat,
        category: ProfileMediaCategory,
        mediaURL: URL? = nil,
        thumbnailURL: URL? = nil,
        coverArtURL: URL? = nil,
        durationSeconds: Double? = nil,
        fileSizeBytes: Int? = nil,
        collaborators: [ProfileMediaCollaborator] = [],
        playCount: Int = 0,
        ratings: [String: Int] = [:],
        pinnedRank: Int? = nil,
        isShared: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.ownerId = ownerId
        self.title = title
        self.caption = caption
        self.format = format
        self.category = category
        self.mediaURL = mediaURL
        self.thumbnailURL = thumbnailURL
        self.coverArtURL = coverArtURL
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
        self.collaborators = collaborators
        self.playCount = playCount
        self.ratings = ratings
        self.pinnedRank = pinnedRank
        self.isShared = isShared
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isPinned: Bool {
        pinnedRank != nil
    }

    var displayCategoryTitle: String {
        category.displayTitle
    }

    var ratingCount: Int {
        ratings.count
    }

    var averageRating: Double {
        guard ratingCount > 0 else { return 0 }
        let total = ratings.values.reduce(0, +)
        return Double(total) / Double(ratingCount)
    }

    func rating(for userId: String?) -> Int? {
        guard let userId else { return nil }
        return ratings[userId]
    }

    func updatingRating(for userId: String, value: Int?) -> ProfileMediaItem {
        var copy = self
        if let value {
            copy.ratings[userId] = max(1, min(value, 5))
        } else {
            copy.ratings.removeValue(forKey: userId)
        }
        copy.updatedAt = Date()
        return copy
    }
}

/// Identifies media collaborators that should be surfaced alongside an uploaded item.
struct ProfileMediaCollaborator: Identifiable, Equatable, Codable {
    enum Kind: String, Codable {
        case user
        case studio
    }

    enum Role: String, CaseIterable, Codable, Identifiable {
        case primaryArtist
        case featuredArtist
        case songwriter
        case producer
        case engineer
        case mixingEngineer
        case masteringEngineer
        case instrumentalist
        case vocalist
        case dj
        case studio
        case other

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .primaryArtist:
                return "Primary artist"
            case .featuredArtist:
                return "Featured artist"
            case .songwriter:
                return "Songwriter"
            case .producer:
                return "Producer"
            case .engineer:
                return "Engineer"
            case .mixingEngineer:
                return "Mixing engineer"
            case .masteringEngineer:
                return "Mastering engineer"
            case .instrumentalist:
                return "Instrumentalist"
            case .vocalist:
                return "Vocalist"
            case .dj:
                return "DJ"
            case .studio:
                return "Studio"
            case .other:
                return "Other"
            }
        }

        var systemImageName: String {
            switch self {
            case .primaryArtist:
                return "person.fill"
            case .featuredArtist:
                return "person.2.fill"
            case .songwriter:
                return "pencil"
            case .producer:
                return "headphones"
            case .engineer:
                return "gearshape"
            case .mixingEngineer:
                return "slider.horizontal.3"
            case .masteringEngineer:
                return "waveform"
            case .instrumentalist:
                return "guitars"
            case .vocalist:
                return "music.mic"
            case .dj:
                return "sparkles"
            case .studio:
                return "building.2"
            case .other:
                return "tag"
            }
        }

        static func suggested(for kind: ProfileMediaCollaborator.Kind) -> [ProfileMediaCollaborator.Role] {
            switch kind {
            case .user:
                return ProfileMediaCollaborator.Role.allCases.filter { $0 != .studio }
            case .studio:
                return [.studio, .other]
            }
        }
    }

    var id: String
    var displayName: String
    var kind: Kind
    var role: Role?
    var accountType: AccountType?

    init(
        id: String,
        displayName: String,
        kind: Kind,
        accountType: AccountType? = nil,
        role: Role? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.accountType = accountType
        self.role = role
    }
}

enum ProfileMediaFormat: String, CaseIterable, Codable {
    case audio
    case video
    case photo
    case gallery

    var iconName: String {
        switch self {
        case .audio:
            return "waveform"
        case .video:
            return "play.rectangle"
        case .photo:
            return "photo"
        case .gallery:
            return "square.grid.2x2"
        }
    }
}

enum ProfileMediaCategory: String, CaseIterable, Codable {
    case song
    case mix
    case master
    case video
    case photo
    case podcast
    case showcase
    case other

    var displayTitle: String {
        switch self {
        case .song:
            return "Song"
        case .mix:
            return "Mix"
        case .master:
            return "Master"
        case .video:
            return "Video"
        case .photo:
            return "Photo"
        case .podcast:
            return "Podcast"
        case .showcase:
            return "Showcase"
        case .other:
            return "Media"
        }
    }

    var defaultFormat: ProfileMediaFormat {
        switch self {
        case .photo:
            return .photo
        case .video:
            return .video
        case .song, .mix, .master, .podcast:
            return .audio
        case .showcase, .other:
            return .gallery
        }
    }
}

struct ProfileMediaCapabilities: Equatable {
    var allowedFormats: [ProfileMediaFormat]
    var defaultCategories: [ProfileMediaCategory]
    var pinLimit: Int
    var pinnedSectionTitle: String
    var pinnedEmptyState: String

    static func forAccountType(_ accountType: AccountType) -> ProfileMediaCapabilities {
        switch accountType {
        case .artist, .producer:
            return ProfileMediaCapabilities(
                allowedFormats: [.audio, .video],
                defaultCategories: [.song, .video],
                pinLimit: 3,
                pinnedSectionTitle: "Pinned Songs",
                pinnedEmptyState: "Pin your top tracks so listeners can play them instantly."
            )
        case .dj:
            return ProfileMediaCapabilities(
                allowedFormats: [.audio, .video],
                defaultCategories: [.mix, .video],
                pinLimit: 3,
                pinnedSectionTitle: "Pinned Mixes",
                pinnedEmptyState: "Pin your signature mixes or sets."
            )
        case .engineer:
            return ProfileMediaCapabilities(
                allowedFormats: [.audio, .video],
                defaultCategories: [.master, .song, .video],
                pinLimit: 3,
                pinnedSectionTitle: "Pinned Masters",
                pinnedEmptyState: "Spotlight select masters or mixes you engineered."
            )
        case .videographer:
            return ProfileMediaCapabilities(
                allowedFormats: [.video],
                defaultCategories: [.video],
                pinLimit: 4,
                pinnedSectionTitle: "Pinned Videos",
                pinnedEmptyState: "Pin standout videos to showcase your directing."
            )
        case .photographer:
            return ProfileMediaCapabilities(
                allowedFormats: [.photo, .gallery],
                defaultCategories: [.photo, .showcase],
                pinLimit: 6,
                pinnedSectionTitle: "Pinned Shots",
                pinnedEmptyState: "Add galleries or highlight photos from recent shoots."
            )
        case .podcast:
            return ProfileMediaCapabilities(
                allowedFormats: [.audio, .video],
                defaultCategories: [.podcast, .video],
                pinLimit: 3,
                pinnedSectionTitle: "Pinned Episodes",
                pinnedEmptyState: "Pin anchor podcast episodes for new listeners."
            )
        case .studioOwner, .eventCenter:
            return ProfileMediaCapabilities(
                allowedFormats: [.photo, .video],
                defaultCategories: [.showcase, .video, .photo],
                pinLimit: 6,
                pinnedSectionTitle: "Venue Highlights",
                pinnedEmptyState: "Pin marquee rooms, stages, or walkthroughs."
            )
        }
    }
}

enum ProfileMediaConstraints {
    static let maxFileSizeBytes = 2 * 1024 * 1024 * 1024
}

extension ProfileMediaItem {
    static func mock(
        ownerId: String = UUID().uuidString,
        format: ProfileMediaFormat = .audio,
        category: ProfileMediaCategory = .song,
        pinnedRank: Int? = nil
    ) -> ProfileMediaItem {
        ProfileMediaItem(
            ownerId: ownerId,
            title: "Demo \(category.displayTitle)",
            caption: "A showcase upload for previews.",
            format: format,
            category: category,
            mediaURL: URL(string: "https://example.com/media/\(UUID().uuidString)"),
            thumbnailURL: format == .photo ? URL(string: "https://example.com/thumbnail/\(UUID().uuidString)") : nil,
            coverArtURL: format == .audio ? URL(string: "https://example.com/cover/\(UUID().uuidString)") : nil,
            durationSeconds: format == .audio ? 182 : nil,
            collaborators: [],
            ratings: [:],
            pinnedRank: pinnedRank,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
