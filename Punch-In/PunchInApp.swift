import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import SwiftUI

@main
@MainActor
struct PunchInApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var playbackManager: MediaPlaybackManager
    @StateObject private var alertsCenter: AlertsCenter
    @StateObject private var uploadManager: ProfileMediaUploadManager
    private let container: DIContainer

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            Firestore.enableLogging(true)
        }
        let container = DIContainer.makeDefault()
        _playbackManager = StateObject(wrappedValue: MediaPlaybackManager(firestoreService: container.firestoreService))
        _alertsCenter = StateObject(wrappedValue: AlertsCenter(alertsService: container.alertsService))
        _uploadManager = StateObject(
            wrappedValue: ProfileMediaUploadManager(
                firestoreService: container.firestoreService
            )
        )
        self.container = container
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(appState)
                .environmentObject(playbackManager)
                .environmentObject(alertsCenter)
                .environmentObject(uploadManager)
                .environment(\.di, container)
                .onOpenURL { url in
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    if let deepLink = DeepLinkParser.parse(url: url) {
                        handle(deepLink)
                    }
                }
        }
    }

    private func handle(_ deepLink: DeepLink) {
        appState.pendingChatThread = nil
        appState.targetBookingID = nil
        appState.targetChatThreadID = nil
        appState.targetMediaID = nil

        switch deepLink {
        case let .bookings(id):
            appState.selectedTab = .book
            appState.targetBookingID = id
        case let .chat(threadId):
            appState.isShowingChat = true
            appState.targetChatThreadID = threadId
        case let .media(mediaId):
            appState.selectedTab = .profile
            appState.targetMediaID = mediaId
        }
    }
}
