import Foundation

@MainActor
final class AlertsCenter: ObservableObject {
    @Published private(set) var alerts: [AppAlert] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var currentUserId: String?

    private let alertsService: any AlertsService
    private var observationTask: Task<Void, Never>?

    init(alertsService: any AlertsService) {
        self.alertsService = alertsService
    }

    func start(for userId: String) {
        guard currentUserId != userId else { return }
        stop()
        currentUserId = userId
        lastError = nil
        isLoading = true

        observationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await alerts in alertsService.observeAlerts(for: userId) {
                    if Task.isCancelled { break }
                    await MainActor.run {
                        self.isLoading = false
                        self.updateAlerts(alerts)
                    }
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        observationTask = nil
        currentUserId = nil
        updateAlerts([])
        lastError = nil
        isLoading = false
    }

    func markAlertAsRead(_ alert: AppAlert) async {
        guard alert.isUnread, let userId = currentUserId else { return }
        do {
            try await alertsService.markAlertAsRead(alertId: alert.id, userId: userId)
        } catch {
            Logger.log("Failed to mark alert as read: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    func markAllAsRead() async {
        guard unreadCount > 0, let userId = currentUserId else { return }
        do {
            try await alertsService.markAllAlertsAsRead(userId: userId)
        } catch {
            Logger.log("Failed to mark alerts as read: \(error.localizedDescription)")
            lastError = error.localizedDescription
        }
    }

    private func updateAlerts(_ newAlerts: [AppAlert]) {
        alerts = newAlerts
        unreadCount = newAlerts.filter(\.isUnread).count
    }

    deinit {
        observationTask?.cancel()
    }
}

#if DEBUG
@MainActor
extension AlertsCenter {
    static func preview(alertsService: MockAlertsService = .preview()) -> AlertsCenter {
        let center = AlertsCenter(alertsService: alertsService)
        center.start(for: "preview-user")
        return center
    }
}
#endif
