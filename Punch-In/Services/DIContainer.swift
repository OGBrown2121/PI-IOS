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
    let bookingService: any BookingService
    let reviewService: any ReviewService

    @MainActor
    static func makeDefault() -> DIContainer {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return makeMock()
        }

        let firestore = FirebaseFirestoreService()
        return DIContainer(
            authService: FirebaseAuthService(),
            firestoreService: firestore,
            storageService: FirebaseStorageService(),
            paymentsService: MockPaymentsService(),
            chatService: FirestoreChatService(
                firestore: Firestore.firestore(),
                storage: Storage.storage(),
                currentUserId: { Auth.auth().currentUser?.uid }
            ),
            bookingService: DefaultBookingService(firestore: firestore),
            reviewService: DefaultReviewService(firestore: firestore)
        )
    }

    @MainActor
    static func makeMock() -> DIContainer {
        let firestore = MockFirestoreService()
        return DIContainer(
            authService: MockAuthService(),
            firestoreService: firestore,
            storageService: MockStorageService(),
            paymentsService: MockPaymentsService(),
            chatService: MockChatService(),
            bookingService: DefaultBookingService(firestore: firestore),
            reviewService: DefaultReviewService(firestore: firestore)
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
