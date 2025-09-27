import Foundation

struct StudioEngineerRequest: Identifiable, Codable, Equatable {
    enum Status: String, Codable, CaseIterable {
        case pending
        case accepted
        case denied

        var displayName: String {
            rawValue.capitalized
        }

        var isFinal: Bool {
            self == .accepted || self == .denied
        }
    }

    var id: String
    var studioId: String
    var engineerId: String
    var studioOwnerId: String
    var status: Status
    var createdAt: Date
    var updatedAt: Date

    var isPending: Bool { status == .pending }
    var isAccepted: Bool { status == .accepted }
}

extension StudioEngineerRequest {
    static func pending(
        id: String,
        studioId: String,
        engineerId: String,
        studioOwnerId: String,
        createdAt: Date = Date()
    ) -> StudioEngineerRequest {
        StudioEngineerRequest(
            id: id,
            studioId: studioId,
            engineerId: engineerId,
            studioOwnerId: studioOwnerId,
            status: .pending,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
