import Foundation

final class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var hasCompletedOnboarding = false
    @Published var currentUser: UserProfile?
    @Published var selectedTab: AppTab = .discovery
    @Published var isShowingChat = false
    @Published var targetBookingID: String?
    @Published var targetChatThreadID: String?
    @Published var targetMediaID: String?
    @Published var pendingChatThread: ChatThread?
}
