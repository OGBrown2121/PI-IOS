import Foundation

struct Studio: Identifiable, Codable, Equatable {
    var id: String
    var ownerId: String
    var name: String
    var city: String
    var address: String
    var hourlyRate: Double?
    var rooms: Int?
    var amenities: [String]
    var coverImageURL: URL?
    var logoImageURL: URL?
    var approvedEngineerIds: [String]

    init(
        id: String = UUID().uuidString,
        ownerId: String,
        name: String,
        city: String,
        address: String = "",
        hourlyRate: Double? = nil,
        rooms: Int? = nil,
        amenities: [String] = [],
        coverImageURL: URL? = nil,
        logoImageURL: URL? = nil,
        approvedEngineerIds: [String] = []
    ) {
        self.id = id
        self.ownerId = ownerId
        self.name = name
        self.city = city
        self.address = address
        self.hourlyRate = hourlyRate
        self.rooms = rooms
        self.amenities = amenities
        self.coverImageURL = coverImageURL
        self.logoImageURL = logoImageURL
        self.approvedEngineerIds = approvedEngineerIds
    }
}

extension Studio {
    static func mock(ownerId: String = UUID().uuidString) -> Studio {
        Studio(
            id: UUID().uuidString,
            ownerId: ownerId,
            name: "Flowstate",
            city: "New York",
            address: "123 Broadway",
            hourlyRate: 75,
            rooms: 3,
            amenities: ["Vocal booth", "Neumann U87", "Lounge"],
            coverImageURL: URL(string: "https://picsum.photos/800/400"),
            logoImageURL: URL(string: "https://picsum.photos/200")
        )
    }

    static let mockList: [Studio] = [
        Studio.mock(),
        Studio(
            id: UUID().uuidString,
            ownerId: UUID().uuidString,
            name: "Pulse",
            city: "Los Angeles",
            address: "456 Sunset Blvd",
            hourlyRate: 90,
            rooms: 4,
            amenities: ["SSL Console", "Parking"],
            coverImageURL: URL(string: "https://picsum.photos/802/400"),
            logoImageURL: URL(string: "https://picsum.photos/202")
        ),
        Studio(
            id: UUID().uuidString,
            ownerId: UUID().uuidString,
            name: "The Booth",
            city: "Austin",
            address: "789 Congress Ave",
            hourlyRate: 65,
            rooms: 2,
            amenities: ["Vintage gear"],
            coverImageURL: URL(string: "https://picsum.photos/804/400"),
            logoImageURL: URL(string: "https://picsum.photos/204")
        )
    ]
}
