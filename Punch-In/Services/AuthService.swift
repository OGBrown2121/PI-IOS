import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit

/// Auth specific failures surfaced to the UI.
enum AuthError: LocalizedError {
    case missingUser
    case missingClientID
    case missingPresenter
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .missingUser:
            return "We couldn't find a valid user in the authentication response."
        case .missingClientID:
            return "Google Sign-In is not configured yet. Add the client ID to your Firebase config."
        case .missingPresenter:
            return "We couldn't find a screen to present the Google Sign-In flow."
        case .missingCredential:
            return "We couldn't create credentials from the sign-in response."
        }
    }
}

/// Manages authentication flows and the currently signed-in user.
protocol AuthService {
    var currentUser: UserProfile? { get }
    @MainActor
    func signInWithApple() async throws -> UserProfile
    @MainActor
    func signInWithGoogle() async throws -> UserProfile
    @MainActor
    func signOut()
}

final class FirebaseAuthService: AuthService {
    private let auth: Auth

    @MainActor
    init() {
        self.auth = Auth.auth()
    }

    @MainActor
    init(auth: Auth) {
        self.auth = auth
    }

    var currentUser: UserProfile? {
        guard let user = auth.currentUser else { return nil }
        return mapUser(user, fallbackUsername: "member")
    }

    func signInWithApple() async throws -> UserProfile {
        let coordinator = SignInWithAppleCoordinator()
        let result = try await coordinator.signIn()
        let appleCredential = result.credential
        let nonce = result.nonce

        guard let tokenData = appleCredential.identityToken,
              let idTokenString = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.missingCredential
        }

        let credential = OAuthProvider.credential(
            withProviderID: "apple.com",
            idToken: idTokenString,
            rawNonce: nonce
        )

        let authResult = try await auth.signIn(with: credential)

        if let fullName = appleCredential.fullName {
            let displayName = fullName.formatted()
            if !displayName.isEmpty {
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try? await changeRequest.commitChanges()
            }
        }

        let fallbackName = appleCredential.fullName?.formatted() ?? "artist"
        return mapUser(authResult.user, fallbackUsername: fallbackName)
    }

    func signInWithGoogle() async throws -> UserProfile {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        guard let presenter = UIApplication.topViewController else {
            throw AuthError.missingPresenter
        }

        let configuration = GIDConfiguration(clientID: clientID)
        let signIn = GIDSignIn.sharedInstance
        signIn.configuration = configuration
        let result = try await signIn.signIn(withPresenting: presenter)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingCredential
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )

        let authResult = try await auth.signIn(with: credential)
        return mapUser(authResult.user, fallbackUsername: result.user.profile?.name ?? "artist")
    }

    func signOut() {
        do {
            try auth.signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            Logger.log("Firebase sign-out failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func signInAnonymously(fallbackUsername: String) async throws -> UserProfile {
        if let existing = auth.currentUser {
            return mapUser(existing, fallbackUsername: fallbackUsername)
        }

        let authResult = try await auth.signInAnonymously()
        return mapUser(authResult.user, fallbackUsername: fallbackUsername)
    }

    private func mapUser(_ user: FirebaseAuth.User, fallbackUsername: String) -> UserProfile {
        let creationDate = user.metadata.creationDate ?? Date()
        let username = user.displayName ?? fallbackUsername
        let displayName = user.displayName ?? "PunchIn Member"
        let profileDetails = AccountProfileDetails()
        return UserProfile(
            id: user.uid,
            username: username,
            displayName: displayName,
            createdAt: creationDate,
            profileImageURL: user.photoURL,
            accountType: .artist,
            profileDetails: profileDetails
        )
    }
}

final class MockAuthService: AuthService {
    private(set) var currentUser: UserProfile?

    func signInWithApple() async throws -> UserProfile {
        try await mockSignIn(provider: "apple")
    }

    func signInWithGoogle() async throws -> UserProfile {
        try await mockSignIn(provider: "google")
    }

    func signOut() {
        currentUser = nil
    }

    private func mockSignIn(provider: String) async throws -> UserProfile {
        try await Task.sleep(nanoseconds: 200_000_000)
        if let existing = currentUser {
            return existing
        }

        let user = UserProfile(
            id: UUID().uuidString,
            username: "punchin_\(provider)",
            displayName: "PunchIn User",
            createdAt: Date(),
            profileImageURL: nil,
            accountType: .artist,
            profileDetails: AccountProfileDetails(
                bio: "Excited to collaborate",
                fieldOne: "Indie",
                fieldTwo: "Songwriter"
            )
        )
        currentUser = user
        return user
    }
}
