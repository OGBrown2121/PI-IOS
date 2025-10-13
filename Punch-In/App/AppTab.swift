import Foundation

enum AppTab: String, CaseIterable, Hashable {
    case discovery
    case events
    case book
    case profile

    var title: String {
        switch self {
        case .discovery: return "Discovery"
        case .events: return "Events"
        case .book: return "Book"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .discovery: return "sparkle.magnifyingglass"
        case .events: return "calendar.badge.clock"
        case .book: return "calendar"
        case .profile: return "person.crop.circle"
        }
    }
}
