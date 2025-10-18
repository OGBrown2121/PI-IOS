import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var threads: [ChatThread] = []
    @Published var threadSearchQuery: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    // New chat state
    @Published var isPresentingNewChat = false
    @Published private(set) var selectedParticipants: [ChatParticipant] = []
    @Published var newChatGroupName: String = ""
    @Published var newChatGroupPhoto: ChatMedia?
    @Published var newChatAllowsParticipantEditing = true
    @Published var newChatIsProject = false
    @Published var newProjectTitle: String = ""
    @Published var newProjectSummary: String = ""
    @Published var newProjectDriveLink: String = ""
    @Published private(set) var isCreatingThread = false

    // Participant search
    @Published private(set) var participantResults: [ChatParticipant] = []
    @Published private(set) var participantQuery: String = ""

    private let chatService: any ChatService
    private let appState: AppState
    private var participantSearchTask: Task<Void, Never>?

    init(chatService: any ChatService, appState: AppState) {
        self.chatService = chatService
        self.appState = appState
    }

    deinit {
        participantSearchTask?.cancel()
    }

    var filteredThreads: [ChatThread] {
        let trimmedQuery = threadSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return threads }
        let loweredQuery = trimmedQuery.lowercased()

        return threads.filter { thread in
            let nameMatch = thread.displayName(currentUserId: currentUserParticipant?.id).lowercased().contains(loweredQuery)
            let messageMatch = thread.lastMessagePreview?.lowercased().contains(loweredQuery) ?? false
            return nameMatch || messageMatch
        }
    }

    var isNewChatGroup: Bool {
        newChatIsProject || selectedParticipants.count > 1
    }

    var isCreatingProject: Bool { newChatIsProject }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let threads = try await chatService.fetchThreads()
            self.threads = threads
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func handleThreadUpdate(_ thread: ChatThread) {
        if let index = threads.firstIndex(where: { $0.id == thread.id }) {
            threads[index] = thread
        } else {
            threads.insert(thread, at: 0)
        }
    }

    func presentNewChat() {
        isPresentingNewChat = true
        selectedParticipants = []
        newChatGroupName = ""
        newChatGroupPhoto = nil
        newChatAllowsParticipantEditing = true
        newChatIsProject = false
        newProjectTitle = ""
        newProjectSummary = ""
        newProjectDriveLink = ""
        updateParticipantQuery("")
    }

    func dismissNewChat() {
        isPresentingNewChat = false
        selectedParticipants = []
        participantResults = []
        participantQuery = ""
        newChatGroupName = ""
        newChatGroupPhoto = nil
        newChatAllowsParticipantEditing = true
        newChatIsProject = false
        newProjectTitle = ""
        newProjectSummary = ""
        newProjectDriveLink = ""
    }

    func updateParticipantQuery(_ query: String) {
        participantQuery = query
        performParticipantSearch()
    }

    func toggleParticipantSelection(_ participant: ChatParticipant) {
        if let index = selectedParticipants.firstIndex(of: participant) {
            selectedParticipants.remove(at: index)
        } else {
            selectedParticipants.append(participant)
        }
        performParticipantSearch()
    }

    func removeParticipant(_ participant: ChatParticipant) {
        guard let index = selectedParticipants.firstIndex(of: participant) else { return }
        selectedParticipants.remove(at: index)
        performParticipantSearch()
    }

    func updateGroupPhoto(_ media: ChatMedia?) {
        newChatGroupPhoto = media
    }

    func createThread() async -> ChatThread? {
        guard !selectedParticipants.isEmpty else {
            errorMessage = "Select at least one participant to start a chat."
            return nil
        }
        guard let creator = currentUserParticipant else {
            errorMessage = "You need an active profile to start a chat."
            return nil
        }

        isCreatingThread = true
        errorMessage = nil

        do {
            let kind: ChatThread.Kind
            if newChatIsProject {
                kind = .project
            } else if selectedParticipants.count > 1 {
                kind = .group
            } else {
                kind = .direct
            }

            var settings: ChatThread.GroupSettings?
            if kind != .direct {
                let trimmedGroupName = newChatGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
                let defaultName = defaultGroupName()
                let resolvedName: String
                if kind == .project {
                    let trimmedProjectTitle = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedProjectTitle.isEmpty {
                        resolvedName = trimmedProjectTitle
                    } else if !trimmedGroupName.isEmpty {
                        resolvedName = trimmedGroupName
                    } else {
                        resolvedName = defaultName
                    }
                } else {
                    resolvedName = trimmedGroupName.isEmpty ? defaultName : trimmedGroupName
                }

                settings = ChatThread.GroupSettings(
                    name: resolvedName,
                    photo: newChatGroupPhoto,
                    allowsParticipantEditing: newChatAllowsParticipantEditing
                )
            }

            var project: ChatThread.Project?
            if kind == .project {
                let trimmedTitle = newProjectTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedTitle.isEmpty else {
                    errorMessage = "Add a title to your project."
                    isCreatingThread = false
                    return nil
                }
                let trimmedSummary = newProjectSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedDrive = newProjectDriveLink.trimmingCharacters(in: .whitespacesAndNewlines)
                var driveURL: URL?
                if !trimmedDrive.isEmpty {
                    let normalizedDrive: String
                    if trimmedDrive.contains("://") {
                        normalizedDrive = trimmedDrive
                    } else {
                        normalizedDrive = "https://\(trimmedDrive)"
                    }
                    guard let parsed = URL(string: normalizedDrive) else {
                        errorMessage = "Enter a valid link for the shared drive."
                        isCreatingThread = false
                        return nil
                    }
                    driveURL = parsed
                }
                project = ChatThread.Project(
                    title: trimmedTitle,
                    summary: trimmedSummary.isEmpty ? nil : trimmedSummary,
                    tasks: [],
                    files: [],
                    sharedDriveURL: driveURL
                )
                if settings == nil {
                    settings = ChatThread.GroupSettings(
                        name: trimmedTitle,
                        photo: newChatGroupPhoto,
                        allowsParticipantEditing: newChatAllowsParticipantEditing
                    )
                }
            }

            let thread = try await chatService.createThread(
                creator: creator,
                participants: selectedParticipants,
                kind: kind,
                groupSettings: settings,
                project: project
            )

            threads.insert(thread, at: 0)
            dismissNewChat()
            isCreatingThread = false
            return thread
        } catch {
            errorMessage = error.localizedDescription
            isCreatingThread = false
            return nil
        }
    }

    private func performParticipantSearch() {
        participantSearchTask?.cancel()
        let query = participantQuery
        let excludedIds = excludedParticipantIds()
        errorMessage = nil

        participantSearchTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            do {
                let results = try await self.chatService.searchParticipants(query: query, excludingIds: excludedIds)
                guard !Task.isCancelled else { return }
                self.participantResults = results
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func excludedParticipantIds() -> Set<String> {
        var ids = Set(selectedParticipants.map(\.id))
        if let currentUserId = currentUserParticipant?.id {
            ids.insert(currentUserId)
        }
        return ids
    }

    private func defaultGroupName() -> String {
        let names = selectedParticipants.map(\.displayName)
        switch names.count {
        case 0: return "New Group"
        case 1: return names[0]
        case 2: return names.joined(separator: " & ")
        default:
            let head = names.prefix(2).joined(separator: ", ")
            return head + " +" + String(names.count - 2)
        }
    }

    private var currentUserParticipant: ChatParticipant? {
        guard let profile = appState.currentUser else { return nil }
        return ChatParticipant(user: profile)
    }

    var currentUserId: String? {
        currentUserParticipant?.id
    }
}
