import Foundation

/// Handles settings actions such as signing out.
@MainActor
final class SettingsViewModel: ObservableObject {
    private let authService: any AuthService
    private let appState: AppState

    init(authService: any AuthService, appState: AppState) {
        self.authService = authService
        self.appState = appState
    }

    func signOut() {
        authService.signOut()
        appState.currentUser = nil
        appState.isAuthenticated = false
        appState.hasCompletedOnboarding = false
    }
}
