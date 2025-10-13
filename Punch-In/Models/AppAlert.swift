import Foundation

struct AppAlert: Identifiable, Codable, Equatable {
    enum Category: String, Codable, CaseIterable {
        case booking
        case chat
        case studio
        case request
        case media
        case system

        var iconName: String {
            switch self {
            case .booking:
                return "calendar.badge.exclamationmark"
            case .chat:
                return "bubble.left.and.bubble.right"
            case .studio:
                return "music.note.house"
            case .request:
                return "person.crop.circle.badge.questionmark"
            case .media:
                return "tray.full"
            case .system:
                return "bell.fill"
            }
        }
    }

    var id: String
    var category: Category
    var title: String
    var message: String
    var createdAt: Date
    var isRead: Bool
    var deeplink: String?

    var isUnread: Bool { isRead == false }
}

#if DEBUG
extension AppAlert {
    static let mock: AppAlert = AppAlert(
        id: UUID().uuidString,
        category: .booking,
        title: "New booking request",
        message: "Studio session on Oct 12 needs your approval.",
        createdAt: Date().addingTimeInterval(-3600),
        isRead: false,
        deeplink: "punchin://bookings"
    )

    static let mockList: [AppAlert] = [
        .mock,
        AppAlert(
            id: UUID().uuidString,
            category: .chat,
            title: "Unread message",
            message: "Thrax House Studio sent a new update.",
            createdAt: Date().addingTimeInterval(-6 * 3600),
            isRead: false,
            deeplink: "punchin://chat/thread/123"
        ),
        AppAlert(
            id: UUID().uuidString,
            category: .request,
            title: "Engineer request approved",
            message: "You’ve been approved to work with Skyline Studios.",
            createdAt: Date().addingTimeInterval(-2 * 24 * 3600),
            isRead: true,
            deeplink: "punchin://studios/skyline"
        ),
        AppAlert(
            id: UUID().uuidString,
            category: .system,
            title: "Profile reminder",
            message: "Add media to your profile to increase visibility.",
            createdAt: Date().addingTimeInterval(-5 * 24 * 3600),
            isRead: true,
            deeplink: nil
        )
    ]
}
#endif
