import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation
import SwiftUI

struct DIContainer {
    let authService: any AuthService
    let firestoreService: any FirestoreService
    let storageService: any StorageService
    let paymentsService: any PaymentsService
    let chatService: any ChatService

    @MainActor
    static func makeDefault() -> DIContainer {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return makeMock()
        }

        return DIContainer(
            authService: FirebaseAuthService(),
            firestoreService: FirebaseFirestoreService(),
            storageService: FirebaseStorageService(),
            paymentsService: MockPaymentsService(),
            chatService: FirestoreChatService(
                firestore: Firestore.firestore(),
                storage: Storage.storage(),
                currentUserId: { Auth.auth().currentUser?.uid }
            )
        )
    }

    @MainActor
    static func makeMock() -> DIContainer {
        DIContainer(
            authService: MockAuthService(),
            firestoreService: MockFirestoreService(),
            storageService: MockStorageService(),
            paymentsService: MockPaymentsService(),
            chatService: MockChatService()
        )
    }
}

private struct DIContainerKey: EnvironmentKey {
    @MainActor static var defaultValue: DIContainer {
        DIContainer.makeMock()
    }
}

extension EnvironmentValues {
    var di: DIContainer {
        get { self[DIContainerKey.self] }
        set { self[DIContainerKey.self] = newValue }
    }
}
