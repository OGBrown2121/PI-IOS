import FirebaseCore
import FirebaseFirestore
import GoogleSignIn
import SwiftUI

@main
@MainActor
struct PunchInApp: App {
    @StateObject private var appState = AppState()
    private let container: DIContainer

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
            Firestore.enableLogging(true)
        }
        container = DIContainer.makeDefault()
    }

    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(appState)
                .environment(\.di, container)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
