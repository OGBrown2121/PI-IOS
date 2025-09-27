import AuthenticationServices
import UIKit

@MainActor
final class SignInWithAppleCoordinator: NSObject {
    typealias AppleSignInResult = (credential: ASAuthorizationAppleIDCredential, nonce: String)
    private var continuation: CheckedContinuation<AppleSignInResult, Error>?
    private var currentNonce: String?

    func signIn() async throws -> AppleSignInResult {
        let nonce = randomNonceString()
        currentNonce = nonce

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AppleSignInResult, Error>) in
            self.continuation = continuation

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

extension SignInWithAppleCoordinator: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce
        else {
            continuation?.resume(throwing: AuthError.missingCredential)
            continuation = nil
            return
        }

        continuation?.resume(returning: (credential, nonce))
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension SignInWithAppleCoordinator: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.keyWindow ?? ASPresentationAnchor()
    }
}
