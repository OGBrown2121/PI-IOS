import Foundation

struct Room: Identifiable, Codable, Equatable {
    var id: String
    var studioId: String
    var name: String
    var description: String
    var hourlyRate: Double?
    var capacity: Int?
    var amenities: [String]
    var isDefault: Bool

    init(
        id: String = UUID().uuidString,
        studioId: String,
        name: String,
        description: String = "",
        hourlyRate: Double? = nil,
        capacity: Int? = nil,
        amenities: [String] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.studioId = studioId
        self.name = name
        self.description = description
        self.hourlyRate = hourlyRate
        self.capacity = capacity
        self.amenities = amenities
        self.isDefault = isDefault
    }
}

extension Room {
    static func mock(studioId: String) -> Room {
        Room(
            studioId: studioId,
            name: "A Room",
            description: "Main tracking room",
            hourlyRate: 85,
            capacity: 4,
            amenities: ["Neve preamps", "Iso booth"],
            isDefault: true
        )
    }
}
