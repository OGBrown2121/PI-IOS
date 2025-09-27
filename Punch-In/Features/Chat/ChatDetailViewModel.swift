import Foundation

@MainActor
final class ChatDetailViewModel: ObservableObject {
    @Published private(set) var thread: ChatThread
    @Published var draftMessage: String = ""
    @Published var isSendingMessage = false
    @Published var isUpdatingSettings = false
    @Published var errorMessage: String?

    private let chatService: any ChatService
    private let appState: AppState
    private let onThreadUpdated: ((ChatThread) -> Void)?

    init(
        thread: ChatThread,
        chatService: any ChatService,
        appState: AppState,
        onThreadUpdated: ((ChatThread) -> Void)? = nil
    ) {
        self.thread = thread
        self.chatService = chatService
        self.appState = appState
        self.onThreadUpdated = onThreadUpdated
    }

    var sortedMessages: [ChatMessage] {
        thread.messages.sorted(by: { $0.sentAt < $1.sentAt })
    }

    var currentUserParticipant: ChatParticipant? {
        guard let profile = appState.currentUser else { return nil }
        return ChatParticipant(user: profile)
    }

    var canEditGroupSettings: Bool {
        guard let currentUserId = currentUserParticipant?.id else { return false }
        return thread.canParticipantEditSettings(currentUserId)
    }

    func refreshThread() async {
        errorMessage = nil
        do {
            let refreshed = try await chatService.thread(withId: thread.id)
            thread = refreshed
            onThreadUpdated?(refreshed)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendTextMessage() async {
        let text = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let sender = currentUserParticipant else {
            errorMessage = "You need an active profile to send a message."
            return
        }
        errorMessage = nil
        isSendingMessage = true
        do {
            let message = try await chatService.sendMessage(
                threadId: thread.id,
                sender: sender,
                content: .text(text)
            )
            updateThread(with: message)
            draftMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingMessage = false
    }

    func sendPhoto(data: Data, caption: String? = nil) async {
        guard let sender = currentUserParticipant else {
            errorMessage = "You need an active profile to send a message."
            return
        }
        errorMessage = nil
        isSendingMessage = true
        let media = ChatMedia(imageData: data)
        do {
            let message = try await chatService.sendMessage(
                threadId: thread.id,
                sender: sender,
                content: .photo(media, caption: caption)
            )
            updateThread(with: message)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSendingMessage = false
    }

    func updateGroupSettings(name: String, photo: ChatMedia?, allowsParticipantEditing: Bool) async {
        guard thread.isGroup else { return }
        guard canEditGroupSettings else {
            errorMessage = "Only the creator can change these settings."
            return
        }
        errorMessage = nil
        isUpdatingSettings = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = ChatThread.GroupSettings(
            name: trimmedName.isEmpty ? thread.displayName() : trimmedName,
            photo: photo,
            allowsParticipantEditing: allowsParticipantEditing
        )
        do {
            let updated = try await chatService.updateGroupSettings(
                threadId: thread.id,
                groupSettings: settings
            )
            thread = updated
            onThreadUpdated?(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdatingSettings = false
    }

    private func updateThread(with message: ChatMessage) {
        var updatedThread = thread
        updatedThread.messages.append(message)
        updatedThread.lastMessageAt = message.sentAt
        thread = updatedThread
        onThreadUpdated?(updatedThread)
    }
}
