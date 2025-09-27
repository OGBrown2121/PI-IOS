import Combine
import FirebaseFirestore
import Foundation

/// Coordinates authentication actions for the sign-in screen.
@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let authService: any AuthService
    private let firestoreService: any FirestoreService
    private let appState: AppState

    init(authService: any AuthService, firestoreService: any FirestoreService, appState: AppState) {
        self.authService = authService
        self.firestoreService = firestoreService
        self.appState = appState
    }

    func signInWithApple() async {
        await performSignIn { try await authService.signInWithApple() }
    }

    func signInWithGoogle() async {
        await performSignIn { try await authService.signInWithGoogle() }
    }

    private func performSignIn(action: () async throws -> UserProfile) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let authProfile = try await action()
            let remoteProfile = try await firestoreService.loadUserProfile(for: authProfile.id)
            let mergedProfile = authProfile.merging(with: remoteProfile)

            try await firestoreService.saveUserProfile(mergedProfile)

            appState.currentUser = mergedProfile
            appState.isAuthenticated = true
            appState.hasCompletedOnboarding = mergedProfile.hasCompletedOnboarding
            Logger.log("Signed in as \(mergedProfile.username)")
        } catch {
            let nsError = error as NSError

            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                errorMessage = "We don't have permission to create your profile yet. Update the Firestore security rules so signed-in users can read and write their own profile documents."
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            Logger.log("Sign-in failed: \(error.localizedDescription)")
        }

        isLoading = false
    }
}
