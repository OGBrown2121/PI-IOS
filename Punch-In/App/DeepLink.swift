import Foundation

enum DeepLink: Equatable {
    case bookings(id: String?)
    case chat(threadId: String)
    case media(mediaId: String)
}

struct DeepLinkParser {
    static func parse(url: URL) -> DeepLink? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "punchin":
            return parseAppScheme(url: url)
        case "https", "http":
            return parseWebURL(url: url)
        default:
            return nil
        }
    }

    private static func parseAppScheme(url: URL) -> DeepLink? {
        let host = (url.host ?? "").lowercased()
        let components = normalizedPathComponents(from: url)

        switch host {
        case "bookings":
            return .bookings(id: components.first)
        case "chat":
            guard let threadId = components.first, !threadId.isEmpty else { return nil }
            return .chat(threadId: threadId)
        case "media":
            guard let mediaId = components.first, !mediaId.isEmpty else { return nil }
            return .media(mediaId: mediaId)
        default:
            return nil
        }
    }

    private static func parseWebURL(url: URL) -> DeepLink? {
        // Support optional universal-link style URLs like https://app.punchin.io/bookings/{id}
        guard let host = url.host?.lowercased() else { return nil }
        let components = normalizedPathComponents(from: url)
        guard components.isEmpty == false else { return nil }

        // Allow any host that contains "punchin"
        guard host.contains("punch") else { return nil }

        let route = components.first?.lowercased()

        switch route {
        case "bookings":
            let bookingId = components.count > 1 ? components[1] : nil
            return .bookings(id: bookingId)
        case "chat":
            guard components.count > 1 else { return nil }
            return .chat(threadId: components[1])
        case "media":
            guard components.count > 1 else { return nil }
            return .media(mediaId: components[1])
        default:
            return nil
        }
    }

    private static func normalizedPathComponents(from url: URL) -> [String] {
        url.pathComponents
            .filter { $0 != "/" }
            .map { component in
                component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
            .filter { !$0.isEmpty }
    }
}
