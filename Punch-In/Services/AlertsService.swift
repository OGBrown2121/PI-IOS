import FirebaseFirestore
import Foundation

protocol AlertsService {
    func observeAlerts(for userId: String) -> AsyncThrowingStream<[AppAlert], Error>
    func markAlertAsRead(alertId: String, userId: String) async throws
    func markAllAlertsAsRead(userId: String) async throws
}

struct FirebaseAlertsService: AlertsService {
    private let database: Firestore

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    func observeAlerts(for userId: String) -> AsyncThrowingStream<[AppAlert], Error> {
        AsyncThrowingStream { continuation in
            let listener = alertsCollection(for: userId)
                .order(by: "createdAt", descending: true)
                .addSnapshotListener { snapshot, error in
                    if let error {
                        continuation.finish(throwing: error)
                        return
                    }
                    guard let snapshot else { return }
                    let alerts = snapshot.documents.map { document in
                        decodeAlert(documentID: document.documentID, data: document.data())
                    }
                    continuation.yield(alerts)
                }

            continuation.onTermination = { _ in
                listener.remove()
            }
        }
    }

    func markAlertAsRead(alertId: String, userId: String) async throws {
        try await alertsCollection(for: userId)
            .document(alertId)
            .setData(
                [
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ],
                merge: true
            )
    }

    func markAllAlertsAsRead(userId: String) async throws {
        let query = try await alertsCollection(for: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()

        guard query.isEmpty == false else { return }

        let batch = database.batch()
        query.documents.forEach { document in
            batch.setData(
                [
                    "isRead": true,
                    "readAt": FieldValue.serverTimestamp()
                ],
                forDocument: document.reference,
                merge: true
            )
        }
        try await batch.commit()
    }

    private func alertsCollection(for userId: String) -> CollectionReference {
        database.collection("users").document(userId).collection("alerts")
    }

    private func decodeAlert(documentID: String, data: [String: Any]) -> AppAlert {
        let categoryRaw = data["category"] as? String ?? AppAlert.Category.system.rawValue
        let category = AppAlert.Category(rawValue: categoryRaw) ?? .system
        let title = data["title"] as? String ?? "Notification"
        let message = data["message"] as? String ?? ""
        let timestamp = data["createdAt"] as? Timestamp
        let createdAt = timestamp?.dateValue() ?? Date()
        let isRead = data["isRead"] as? Bool ?? false
        let deeplink = data["deeplink"] as? String

        return AppAlert(
            id: documentID,
            category: category,
            title: title,
            message: message,
            createdAt: createdAt,
            isRead: isRead,
            deeplink: deeplink
        )
    }
}

final class MockAlertsService: AlertsService {
    private var storedAlerts: [String: [AppAlert]] = [:]
    private var streams: [String: [UUID: AsyncThrowingStream<[AppAlert], Error>.Continuation]] = [:]

    func observeAlerts(for userId: String) -> AsyncThrowingStream<[AppAlert], Error> {
        AsyncThrowingStream { continuation in
            let token = UUID()
            continuation.yield(storedAlerts[userId] ?? [])
            var userStreams = streams[userId] ?? [:]
            userStreams[token] = continuation
            streams[userId] = userStreams
            continuation.onTermination = { [weak self] _ in
                self?.streams[userId]?[token] = nil
                if self?.streams[userId]?.isEmpty == true {
                    self?.streams[userId] = nil
                }
            }
        }
    }

    func markAlertAsRead(alertId: String, userId: String) async throws {
        guard var alerts = storedAlerts[userId],
              let index = alerts.firstIndex(where: { $0.id == alertId }) else { return }
        alerts[index].isRead = true
        storedAlerts[userId] = alerts
        notify(userId: userId)
    }

    func markAllAlertsAsRead(userId: String) async throws {
        guard var alerts = storedAlerts[userId] else { return }
        alerts = alerts.map { alert in
            var copy = alert
            copy.isRead = true
            return copy
        }
        storedAlerts[userId] = alerts
        notify(userId: userId)
    }

    func setAlerts(_ alerts: [AppAlert], for userId: String) {
        storedAlerts[userId] = alerts
        notify(userId: userId)
    }

    private func notify(userId: String) {
        guard let alerts = storedAlerts[userId] else {
            streams[userId]?.values.forEach { $0.yield([]) }
            return
        }
        streams[userId]?.values.forEach { $0.yield(alerts) }
    }
}

#if DEBUG
extension MockAlertsService {
    static func preview(with userId: String = "preview-user") -> MockAlertsService {
        let service = MockAlertsService()
        service.setAlerts(AppAlert.mockList, for: userId)
        return service
    }
}
#else
extension MockAlertsService {
    static func preview(with userId: String = "preview-user") -> MockAlertsService {
        MockAlertsService()
    }
}
#endif
