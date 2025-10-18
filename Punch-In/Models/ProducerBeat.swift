import Foundation

/// Represents a single beat listed by a producer for purchase or licensing.
struct ProducerBeat: Identifiable, Codable, Equatable {
    enum License: String, CaseIterable, Codable, Identifiable {
        case exclusive
        case nonExclusive
        case stemsIncluded
        case custom

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .exclusive:
                return "Exclusive License"
            case .nonExclusive:
                return "Non-Exclusive License"
            case .stemsIncluded:
                return "Stems Included"
            case .custom:
                return "Custom Terms"
            }
        }

        var iconName: String {
            switch self {
            case .exclusive:
                return "seal.fill"
            case .nonExclusive:
                return "rectangle.stack.fill"
            case .stemsIncluded:
                return "waveform.path.ecg"
            case .custom:
                return "doc.richtext"
            }
        }
    }

    var id: String
    var producerId: String
    var title: String
    var summary: String
    var license: License
    var primaryGenre: MusicGenre?
    var priceCents: Int
    var currencyCode: String
    var previewURL: URL?
    var artworkURL: URL?
    var bpm: Int?
    var musicalKey: String?
    var durationSeconds: Double?
    var stemsIncluded: Bool
    var stemsZipURL: URL?
    var tags: [String]
    var allowFreeDownload: Bool
    var isPublished: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        producerId: String,
        title: String,
        summary: String = "",
        license: License = .nonExclusive,
        primaryGenre: MusicGenre? = nil,
        priceCents: Int,
        currencyCode: String = "USD",
        previewURL: URL? = nil,
        artworkURL: URL? = nil,
        bpm: Int? = nil,
        musicalKey: String? = nil,
        durationSeconds: Double? = nil,
        stemsIncluded: Bool = false,
        stemsZipURL: URL? = nil,
        tags: [String] = [],
        allowFreeDownload: Bool = false,
        isPublished: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.producerId = producerId
        self.title = title
        self.summary = summary
        self.license = license
        self.primaryGenre = primaryGenre
        self.priceCents = priceCents
        self.currencyCode = currencyCode
        self.previewURL = previewURL
        self.artworkURL = artworkURL
        self.bpm = bpm
        self.musicalKey = musicalKey
        self.durationSeconds = durationSeconds
        self.stemsIncluded = stemsIncluded
        self.stemsZipURL = stemsZipURL
        self.tags = tags
        self.allowFreeDownload = allowFreeDownload
        self.isPublished = isPublished
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedPrice: String {
        formattedPrice()
    }

    func formattedPrice(locale: Locale = .current) -> String {
        let formatter = ProducerBeat.makeCurrencyFormatter(locale: locale, currencyCode: currencyCode)
        let amount = Double(priceCents) / 100
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(String(format: "%.2f", amount))"
    }

    var detailLine: String {
        var components: [String] = []
        if let bpm {
            components.append("\(bpm) BPM")
        }
        if let musicalKey, musicalKey.isEmpty == false {
            components.append(musicalKey.uppercased())
        }
        if stemsIncluded {
            components.append("Stems")
        }
        return components.joined(separator: " • ")
    }

    var displayTags: String {
        tags.isEmpty ? "" : tags.joined(separator: ", ")
    }

    var sanitizedTags: [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    func updatingMedia(previewURL: URL?, artworkURL: URL?, stemsZipURL: URL? = nil) -> ProducerBeat {
        var copy = self
        copy.previewURL = previewURL
        copy.artworkURL = artworkURL
        if let stemsZipURL {
            copy.stemsZipURL = stemsZipURL
        }
        copy.updatedAt = Date()
        copy.tags = sanitizedTags
        return copy
    }

    var genreDisplayName: String? {
        primaryGenre?.displayName
    }

    var isFreeDownloadEnabled: Bool {
        priceCents == 0 || allowFreeDownload
    }

    private static func makeCurrencyFormatter(locale: Locale, currencyCode: String) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }
}

struct BeatDownloadRequest: Identifiable, Codable, Equatable {
    enum Status: String, CaseIterable, Codable, Identifiable {
        case pending
        case fulfilled
        case rejected

        var id: String { rawValue }

        var displayTitle: String {
            switch self {
            case .pending:
                return "Pending"
            case .fulfilled:
                return "Fulfilled"
            case .rejected:
                return "Rejected"
            }
        }
    }

    var id: String
    var beatId: String
    var producerId: String
    var requesterId: String
    var beatTitle: String?
    var downloadURL: URL?
    var status: Status
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        beatId: String,
        producerId: String,
        requesterId: String,
        beatTitle: String? = nil,
        downloadURL: URL? = nil,
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.beatId = beatId
        self.producerId = producerId
        self.requesterId = requesterId
        self.beatTitle = beatTitle
        self.downloadURL = downloadURL
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ProducerBeat {
    static let mock = ProducerBeat(
        producerId: "producer_123",
        title: "Midnight Drive",
        summary: "Moody trap drums with analog synth textures.",
        license: .nonExclusive,
        priceCents: 3499,
        previewURL: URL(string: "https://example.com/midnight-drive-preview.mp3"),
        bpm: 142,
        musicalKey: "Fm",
        durationSeconds: 126,
        stemsIncluded: true,
        tags: ["Trap", "Moody", "Synthwave"],
        allowFreeDownload: false
    )

    static let exclusiveMock = ProducerBeat(
        producerId: "producer_123",
        title: "Sunset Skies",
        summary: "Warm R&B chords with live bass and crisp percussion.",
        license: .exclusive,
        priceCents: 12500,
        previewURL: URL(string: "https://example.com/sunset-skies-preview.mp3"),
        bpm: 94,
        musicalKey: "Bbmaj",
        durationSeconds: 188,
        stemsIncluded: false,
        tags: ["R&B", "Soulful", "Live Bass"],
        allowFreeDownload: false
    )
}
