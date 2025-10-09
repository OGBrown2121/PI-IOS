import Foundation

struct ProfileSpotlight: Identifiable, Equatable, Codable {
    static let eventVisibilityWindowDays: Int = 1

    enum Category: String, CaseIterable, Codable {
        case project
        case event

        var title: String {
            switch self {
            case .project:
                return "Project"
            case .event:
                return "Event"
            }
        }

        var systemImageName: String {
            switch self {
            case .project:
                return "hammer"
            case .event:
                return "calendar"
            }
        }
    }

    var id: String
    var category: Category
    var title: String
    var detail: String
    var scheduledAt: Date?
    var location: String
    var callToActionTitle: String
    var callToActionURL: URL?

    init(
        id: String = UUID().uuidString,
        category: Category,
        title: String = "",
        detail: String = "",
        scheduledAt: Date? = nil,
        location: String = "",
        callToActionTitle: String = "",
        callToActionURL: URL? = nil
    ) {
        self.id = id
        self.category = category
        self.title = title
        self.detail = detail
        self.scheduledAt = scheduledAt
        self.location = location
        self.callToActionTitle = callToActionTitle
        self.callToActionURL = callToActionURL
    }

    var isDisplayable: Bool {
        !title.trimmed.isEmpty
    }

    var expirationDate: Date? {
        guard case .event = category, let scheduledAt else { return nil }
        return Calendar.current.date(byAdding: .day, value: Self.eventVisibilityWindowDays, to: scheduledAt)
    }

    func isActive(on referenceDate: Date = Date()) -> Bool {
        guard isDisplayable else { return false }
        switch category {
        case .project:
            return true
        case .event:
            guard let scheduledAt else { return false }
            let expiry = expirationDate ?? scheduledAt
            return expiry >= referenceDate
        }
    }
}

extension Array where Element == ProfileSpotlight {
    func sanitized(referenceDate: Date = Date()) -> [ProfileSpotlight] {
        filter { $0.isActive(on: referenceDate) }
            .map { item in
                var copy = item
                if copy.callToActionTitle.trimmed.isEmpty && copy.callToActionURL != nil {
                    copy.callToActionTitle = "Learn more"
                }
                return copy
            }
    }
}
